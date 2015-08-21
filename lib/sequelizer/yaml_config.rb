require 'psych'
require 'pathname'

module Sequelizer
  class YamlConfig
    attr_reader :config_file_path

    class << self
      def local_config
        new
      end

      def user_config
        new(user_config_path)
      end

      def user_config_path
        Pathname.new("~") + ".config" + "sequelizer" + "database.yml"
      end
    end

    def initialize(config_file_path = nil)
      @config_file_path = Pathname.new(config_file_path || Pathname.pwd + "config" + "database.yml").expand_path
    end

    # Returns a set of options pulled from config/database.yml
    # or +nil+ if config/database.yml doesn't exist
    def options
      return {} unless config_file_path.exist?
      config['adapter'] || config[:adapter] ? config : config[environment]
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

    # The config as read from config/database.yml
    def config
      @config ||= Psych.load_file(config_file_path)
    end
  end
end
