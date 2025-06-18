require_relative 'yaml_config'
require_relative 'env_config'
require_relative 'options_hash'

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
    #   If a String is provided, it's treated as a database URL and returned as-is.
    #   If nil, configuration is loaded entirely from external sources.
    def initialize(options = nil)
      opts = fix_options(options)
      @options, @extensions = filter_extensions(opts)
    end

    # Returns the processed options as a hash suitable for Sequel.connect.
    #
    # @return [Hash] the database connection options
    def to_hash
      @options
    end

    # Define accessor methods for common database options
    %w[adapter database username password search_path].each do |name|
      # @!method #{name}
      #   @return [String, nil] the #{name} option value
      define_method(name) do
        @options[name]
      end
    end

    private

    # Creates an after_connect callback proc that handles custom callbacks
    # and applies database-specific options.
    #
    # @param opts [Hash] options hash that may contain an :after_connect callback
    # @return [Proc] callback to be executed after database connection
    def make_ac(opts)
      proc do |conn, server, db|
        if (ac = opts[:after_connect])
          ac.arity == 2 ? ac.call(conn, server) : ac.call(conn)
        end
        db.extension :db_opts
        db.db_opts.apply(conn)
      end
    end

    # Processes and fixes the passed options, handling various input types
    # and applying adapter-specific transformations.
    #
    # If passed a hash, scans hash for certain options and sets up hash
    # to be fed to Sequel.connect. Handles PostgreSQL schema setup and
    # timeout conversion.
    #
    # If passed anything else (like a string that represents a database URL),
    # the value is returned without modification.
    #
    # @param passed_options [Hash, String, nil] the options to process
    # @return [Hash, String] processed options or original string
    def fix_options(passed_options)
      return passed_options unless passed_options.nil? || passed_options.is_a?(Hash)

      opts = OptionsHash.new(passed_options || {}).to_hash
      sequelizer_options = db_config(opts).merge(opts)

      if sequelizer_options[:adapter] =~ /^postgres/
        sequelizer_options[:adapter] = 'postgres'
        paths = %w[search_path schema_search_path schema].map { |key| sequelizer_options.delete(key) }.compact

        unless paths.empty?
          sequelizer_options[:search_path] = paths.first
          sequelizer_options[:after_connect] = after_connect(paths.first)
        end
      end

      if sequelizer_options[:timeout]
        # I'm doing a merge! here because the indifferent access part
        # of OptionsHash seemed to not work when I tried
        # sequelizer_options[:timeout] = sequelizer_options[:timeout].to_i
        sequelizer_options.merge!(timeout: sequelizer_options[:timeout].to_i)
      end

      sequelizer_options.merge(after_connect: make_ac(sequelizer_options))
    end

    # Loads database configuration from external sources in order of precedence.
    # Sources checked (in order):
    # - ~/.config/sequelizer.yml (if it exists and not ignored)
    # - config/database.yml (if it exists and not ignored)
    # - environment variables (including .env file if not ignored)
    #
    # @param opts [Hash] base options that may contain ignore flags
    # @return [OptionsHash] merged configuration from all sources
    def db_config(opts)
      @db_config ||= begin
        opts = OptionsHash.new(opts)
        opts.merge!(YamlConfig.user_config.options) unless opts[:ignore_yaml]
        opts.merge!(YamlConfig.local_config.options) unless opts[:ignore_yaml]
        opts.merge!(EnvConfig.new.options) unless opts[:ignore_env]
        opts
      end
    end

    # Returns a proc that should be executed after Sequel connects to the
    # database.
    #
    # For PostgreSQL connections with a search_path defined, this proc will:
    # 1. Create each schema in the search path if it doesn't exist
    # 2. Set the search_path for the connection
    #
    # @param search_path [String] comma-separated list of PostgreSQL schemas
    # @return [Proc] callback to execute after connection
    # @example
    #   callback = after_connect('public,app_schema')
    #   # When called, creates schemas and sets search_path
    def after_connect(search_path)
      proc do |conn|
        search_path.split(',').map(&:strip).each do |schema|
          conn.execute("CREATE SCHEMA IF NOT EXISTS #{schema}")
        end
        conn.execute("SET search_path TO #{search_path}")
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
        key.to_s.gsub(extension_regexp, '').to_sym
      end
      [options, extensions]
    end

  end
end
