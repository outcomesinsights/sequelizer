require "psych"
require "erb"

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
        return nil unless Dir.home

        Pathname.new(Dir.home).join(".config", "sequelizer", "database.yml")
      end
    end

    def initialize(config_file_path = nil)
      @config_file_path = Pathname.new(config_file_path || Pathname.pwd.join("config", "sequelizer.yml")).expand_path
    end

    # Returns a set of options pulled from the YAML file at +config_file_path+
    # (config/sequelizer.yml by default), or an empty hash if that file
    # doesn't exist
    def options
      return {} unless config_file_path.exist?

      config[environment] || config
    end

    # The environment to load from the YAML file
    #
    # Searches the following environment variables in this order:
    # * SEQUELIZER_ENV
    # * RAILS_ENV
    # * RACK_ENV
    #
    # Lastly, if none of those environment variables are specified, the
    # environment defaults to 'development'
    def environment
      ENV["SEQUELIZER_ENV"] || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
    end

    private

    # The config as read from the YAML file at +config_file_path+
    def config
      @config ||= Psych.load(ERB.new(File.read(config_file_path)).result)
    end
  end
end
