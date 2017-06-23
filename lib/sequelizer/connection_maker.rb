require 'sequel'
require_relative 'options'

module Sequelizer
  # Class that handles loading/interpretting the database options and
  # creates the Sequel connection
  class ConnectionMaker
    # The options for Sequel.connect
    attr :options

    # Accepts an optional set of database options
    #
    # If no options are provided, attempts to read options from
    # config/database.yml
    #
    # If config/database.yml doesn't exist, Dotenv is used to try to load a
    # .env file, then uses any SEQUELIZER_* environment variables as
    # database options
    def initialize(options = nil)
      @options = Options.new(options)
    end

    # Returns a Sequel connection to the database
    def connection
      opts = options.to_hash
      conn = if url = (opts.delete(:uri) || opts.delete(:url))
        Sequel.connect(url, opts)
      else
        Sequel.connect(options.to_hash)
      end
      apply_config(conn, opts)
      conn
    end

    private

    def apply_config(conn, opts = {})
      db_opts_from(conn, opts).each do |option, value|
        conn.run("SET #{option} = #{value}")
      end
    end

    def db_opts_from(conn, opts)
      opt_regexp = /^#{conn.database_type}_db_opt_/i

      matching_opts = opts.select { |k, _| k.to_s.match(opt_regexp) }

      matching_opts.each_with_object({}) do |(k,v), h|
        new_key = k.sub(opt_regexp, '')
        h[new_key] = prep_value(k, v)
      end
    end

    def prep_value(k, v)
      v =~ /\W/ ? %Q|"#{v}"| : v
    end
  end
end
