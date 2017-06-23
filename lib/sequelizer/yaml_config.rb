require 'psych'
require 'pathname'
require 'erb'

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
        return nil unless ENV['HOME']
        Pathname.new(ENV['HOME']) + ".config" + "sequelizer" + "database.yml"
      end
    end

    def initialize(config_file_path = nil)
      @config_file_path = Pathname.new(config_file_path || Pathname.pwd + "config" + "sequelizer.yml").expand_path
    end

    # Returns a set of options pulled from config/database.yml
    # or +nil+ if config/database.yml doesn't exist
    def options
      return {} unless config_file_path.exist?
      config[environment] || config
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
      @config ||= Psych.load(ERB.new(File.read(config_file_path)).result)
    end
  end
end
