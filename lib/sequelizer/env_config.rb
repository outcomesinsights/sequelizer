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

      seq_config = ENV.keys.grep(/^SEQUELIZER_/).each_with_object({}) do |key, config|
        new_key = key.gsub(/^SEQUELIZER_/, '').downcase
        config[new_key] = ENV.fetch(key, nil)
      end

      db_config = ENV.keys.grep(/_DB_OPT_/).each_with_object({}) do |key, config|
        new_key = key.downcase
        config[new_key] = ENV.fetch(key, nil)
      end

      db_config.merge(seq_config)
    end

  end
end
