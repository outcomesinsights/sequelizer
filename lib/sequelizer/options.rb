require 'sequelizer/yaml_config'
require 'sequelizer/env_config'

module Sequelizer
  class Options
    def initialize(options = nil)
      @options = fix_options(options || db_config)
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

    # If passed a hash, scans hash for certain options and sets up hash
    # to be fed to Sequel.connect
    #
    # If fed anything, like a string that represents the URL for a DB,
    # the string is returned without modification
    def fix_options(sequelizer_options)
      return sequelizer_options unless sequelizer_options.is_a?(Hash)

      search_path = sequelizer_options['search_path'] || sequelizer_options['schema_search_path']
      sequelizer_options['adapter'] = 'postgres' if sequelizer_options['adapter'] =~ /^postgres/
      if search_path && sequelizer_options['adapter'] =~ /postgres/i
        sequelizer_options['after_connect'] = after_connect(search_path)
      end

      sequelizer_options
    end

    # Grabs the database options from
    #  - config/database.yml if it exists
    #  - environment variables (also reads from .env)
    def db_config
      @db_config ||= begin
        YamlConfig.new.options || EnvConfig.new.options
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
  end
end
