require 'psych'
require 'pathname'

module Sequelizer
  class YamlConfig
    # Returns a set of options pulled from config/database.yml
    # or +nil+ if config/database.yml doesn't exist
    def options
      return {} unless config_file.exist?
      config['adapter'] ? config : config[environment]
    end

    # The environment to load from database.yml
    #
    # Searches the following environment variables in this order:
    # * SEQUELIZER_ENV
    # * RAILS_ENV
    # * RACK_ENV
    #
    # Lastly, if none of those environment variables are specified, the
    # environment defaults to 'development'
    def environment
      ENV['SEQUELIZER_ENV'] || ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
    end

    private

    # The Pathname to config/database.yml
    def config_file
      @config_file ||= begin
        root + 'config' + 'database.yml'
      end
    end

    # The root directory to search for config/database.yml
    def root
      @root ||= Pathname.pwd
    end

    # The config as read from config/database.yml
    def config
      @config ||= Psych.load_file(config_file)
    end
  end
end
