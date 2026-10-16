require "uri"
require_relative "yaml_config"
require_relative "env_config"

module Sequelizer
  # = Options
  #
  # Manages database connection options from multiple configuration sources.
  # This class is responsible for:
  #
  # * Loading configuration from various sources (YAML files, environment variables, .env files)
  # * Applying precedence rules for configuration sources
  # * Processing adapter-specific options (especially PostgreSQL schema handling)
  # * Managing Sequel extensions
  # * Setting up after_connect callbacks
  #
  # == Configuration Sources (in order of precedence)
  #
  # 1. Passed options (highest priority)
  # 2. .env file
  # 3. Environment variables
  # 4. config/database.yml
  # 5. ~/.config/sequelizer/database.yml (lowest priority)
  #
  # @example Basic usage
  #   options = Options.new(adapter: 'postgres', host: 'localhost')
  #   hash = options.to_hash
  #
  # @example Loading from environment
  #   ENV['SEQUELIZER_ADAPTER'] = 'postgres'
  #   options = Options.new
  #   puts options.adapter  # => 'postgres'
  class Options
    # @!attribute [r] extensions
    #   @return [Array<Symbol>] list of Sequel extensions to load
    attr_reader :extensions

    # Creates a new Options instance, processing configuration from multiple sources.
    #
    # @param options [Hash, String, nil] database connection options or connection URL
    #   If a Hash is provided, it will be merged with configuration from other sources.
    #   If a String is provided, it is a database URL, the way Sequel.connect accepts one:
    #   <tt>Options.new("postgres://host/db")</tt> is the same as
    #   <tt>Options.new(url: "postgres://host/db")</tt>, so it is merged with the other
    #   sources too.
    #   If nil, configuration is loaded entirely from external sources.
    def initialize(options = nil)
      opts = fix_options(options)
      @options, @extensions = filter_extensions(opts)
    end

    # Returns the processed options as a hash suitable for Sequel.connect.
    #
    # @return [Hash{Symbol => Object}] the database connection options, keyed by Symbol
    def to_hash
      @options
    end

    # Define accessor methods for common database options
    %i[adapter database username password search_path].each do |name|
      # @!method #{name}
      #   @return [String, nil] the #{name} option value
      define_method(name) do
        @options[name]
      end
    end

    private

    # Processes and fixes the passed options, handling various input types
    # and applying adapter-specific transformations.
    #
    # Scans the options for certain keys and sets up a hash to be fed to
    # Sequel.connect. Handles PostgreSQL schema setup and timeout conversion.
    # A String is a database URL and is processed as <tt>{ url: string }</tt>.
    #
    # @param passed_options [Hash, String, nil] the options to process
    # @return [Hash{Symbol => Object}] processed options
    def fix_options(passed_options)
      passed_options = { url: passed_options } if passed_options.is_a?(String)
      opts = symbolize_keys(passed_options || {})
      sequelizer_options = db_config(opts).merge(opts)

      adapter = sequelizer_options[:adapter]
      adapter ||= URI.parse(sequelizer_options[:url].to_s).scheme if sequelizer_options[:url]

      if adapter =~ /^postgres/
        sequelizer_options[:adapter] = "postgres"
        paths = %i[search_path schema_search_path schema].map { |key| sequelizer_options.delete(key) }.compact

        unless paths.empty?
          sequelizer_options[:search_path] = paths.first
          sequelizer_options[:after_connect] = after_connect(paths.first)
        end
      end

      sequelizer_options[:timeout] = sequelizer_options[:timeout].to_i if sequelizer_options[:timeout]

      sequelizer_options
    end

    # Loads database configuration from external sources in order of precedence.
    # Sources checked (in order):
    # - ~/.config/sequelizer.yml (if it exists and not ignored)
    # - config/database.yml (if it exists and not ignored)
    # - environment variables (including .env file if not ignored)
    #
    # @param opts [Hash] base options that may contain ignore flags
    # @return [Hash{Symbol => Object}] merged configuration from all sources
    def db_config(opts)
      @db_config ||= begin
        opts = opts.dup
        opts.merge!(symbolize_keys(YamlConfig.user_config.options)) unless opts[:ignore_yaml]
        opts.merge!(symbolize_keys(YamlConfig.local_config.options)) unless opts[:ignore_yaml]
        opts.merge!(symbolize_keys(EnvConfig.new.options)) unless opts[:ignore_env]
        opts
      end
    end

    # Returns a copy of +value+ with every Hash key, at any depth, converted
    # to a Symbol. Options arrive with String keys from YAML, ENV, and some
    # callers; Sequel expects Symbols, including for nested hashes such as
    # +:servers+, which it indexes by server name.
    #
    # @param value [Object] a Hash, an Array, or any other value
    # @return [Object] the converted copy; the caller's objects are not modified
    def symbolize_keys(value)
      case value
      when Hash then value.to_h { |k, v| [ k.to_sym, symbolize_keys(v) ] }
      when Array then value.map { |v| symbolize_keys(v) }
      else value
      end
    end

    # Returns a proc that should be executed after Sequel connects to the
    # database.
    #
    # For PostgreSQL connections with a search_path defined, this proc will:
    # 1. Create each schema in the search path if it doesn't exist
    # 2. Set the search_path for the connection
    #
    # @param search_path [String, Array<String>] PostgreSQL schema names as a
    #   comma-separated string, an Array of schema names, or a mixed Array
    #   containing comma-separated strings
    # @return [Proc] callback to execute after connection
    # @example String input
    #   callback = after_connect('public,app_schema')
    # @example Array input
    #   callback = after_connect(['public', 'app_schema'])
    def after_connect(search_path)
      schemas = Array(search_path).flat_map { |p| p.to_s.split(",") }.map(&:strip)
      path_string = schemas.join(", ")
      proc do |conn|
        schemas.each do |schema|
          conn.execute("CREATE SCHEMA IF NOT EXISTS #{schema}")
        end
        conn.execute("SET search_path TO #{path_string}")
      end
    end

    # Extracts Sequel extension configuration from options.
    #
    # Looks for keys starting with 'extension_' and converts them to
    # extension names. The extension keys are removed from the options
    # hash and returned separately.
    #
    # @param options [Hash] options hash that may contain extension keys
    # @return [Array<Hash, Array>] tuple of [filtered_options, extensions]
    # @example
    #   opts = { adapter: 'postgres', extension_pg_json: true, extension_pg_array: true }
    #   filtered_opts, exts = filter_extensions(opts)
    #   # filtered_opts => { adapter: 'postgres' }
    #   # exts => [:pg_json, :pg_array]
    def filter_extensions(options)
      extension_regexp = /^extension_/
      extension_keys = options.keys.select { |k| k.to_s =~ extension_regexp }
      extensions = extension_keys.map do |key|
        options.delete(key)
        key.to_s.gsub(extension_regexp, "").to_sym
      end
      [ options, extensions ]
    end
  end
end
