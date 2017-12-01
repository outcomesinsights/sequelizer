require_relative 'yaml_config'
require_relative 'env_config'
require_relative 'options_hash'

module Sequelizer
  class Options
    attr :extensions
    def initialize(options = nil)
      opts = fix_options(options)
      @options, @extensions = filter_extensions(opts)
    end

    def to_hash
      @options
    end

    %w(adapter database username password search_path).each do |name|
      define_method(name) do
        @options[name]
      end
    end

    private

    def make_ac(opts)
      Proc.new do |conn, server, db|
        if ac = opts[:after_connect]
          ac.arity == 2 ? ac.call(conn, server) : ac.call(conn)
        end
        db.extension :db_opts
        db.db_opts.apply(conn)
      end
    end

    # If passed a hash, scans hash for certain options and sets up hash
    # to be fed to Sequel.connect
    #
    # If fed anything, like a string that represents the URL for a DB,
    # the string is returned without modification
    def fix_options(passed_options)
      return passed_options unless passed_options.nil? || passed_options.is_a?(Hash)
      sequelizer_options = db_config.merge(OptionsHash.new(passed_options || {}).to_hash)

      if sequelizer_options[:adapter] =~ /^postgres/
        sequelizer_options[:adapter] = 'postgres'
        paths = %w(search_path schema_search_path schema).map { |key| sequelizer_options.delete(key) }.compact

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

    # Grabs the database options from
    #  - ~/.config/sequelizer.yml if it exists
    #  - config/database.yml if it exists
    #  - environment variables (also reads from .env)
    def db_config
      @db_config ||= begin
        opts = OptionsHash.new(YamlConfig.user_config.options)
        opts.merge!(YamlConfig.local_config.options)
        opts.merge!(EnvConfig.new.options)
        opts
      end
    end

    # Returns a proc that should be executed after Sequel connects to the
    # datebase.
    #
    # Right now, the only thing that happens is if we're connecting to
    # PostgreSQL and the schema_search_path is defined, each schema
    # is created if it doesn't exist, then the search_path is set for
    # the connection.
    def after_connect(search_path)
      Proc.new do |conn|
        search_path.split(',').map(&:strip).each do |schema|
          conn.execute("CREATE SCHEMA IF NOT EXISTS #{schema}")
        end
        conn.execute("SET search_path TO #{search_path}")
      end
    end

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
