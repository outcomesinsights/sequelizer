require 'dotenv'

module Sequelizer
  # Creates a set of database configuration options from environment
  # variables
  class EnvConfig
    # Any environment variables in the .env file are loaded and then
    # any environment variable starting with SEQUELIZER_ will be used
    # as an option for the database
    def options
      Dotenv.load
      env_config = ENV.keys.select { |key| key =~ /^SEQUELIZER_/ }.inject({}) do |config, key|
        new_key = key.gsub(/^SEQUELIZER_/, '').downcase
        config[new_key] = ENV[key]
        config
      end
      env_config.empty? ? nil : env_config
    end
  end
end
