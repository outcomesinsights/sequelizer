require "sequel"
require_relative "options"

module Sequelizer
  # = ConnectionMaker
  #
  # Class that handles loading/interpreting the database options and
  # creates the Sequel connection. This class is responsible for:
  #
  # * Loading configuration from multiple sources
  # * Creating standard Sequel database connections
  #
  # @example Basic usage
  #   maker = ConnectionMaker.new(adapter: 'postgres', host: 'localhost')
  #   db = maker.connection
  class ConnectionMaker
    # @!attribute [r] options
    #   @return [Options] the database connection options
    attr_reader :options

    # Creates a new ConnectionMaker instance.
    #
    # If no options are provided, attempts to read options from multiple sources
    # in order of precedence:
    # 1. .env file
    # 2. Environment variables
    # 3. config/database.yml
    # 4. ~/.config/sequelizer/database.yml
    #
    # @param options [Hash, String, nil] database connection options, or a
    #   database URL String, which is the same as passing <tt>{ url: string }</tt>
    # @option options [String] :adapter database adapter (e.g., 'postgres', 'mysql2')
    # @option options [String] :host database host
    # @option options [Integer] :port database port
    # @option options [String] :database database name
    # @option options [String] :username database username
    # @option options [String] :password database password
    # @option options [String] :search_path PostgreSQL schema search path
    def initialize(options = nil)
      @options = Options.new(options)
    end

    # Returns a Sequel connection to the database.
    #
    # This method creates a standard Sequel database connection
    # using the configured options.
    #
    # @return [Sequel::Database] configured database connection
    # @raise [Sequel::Error] if connection fails
    #
    # @example
    #   connection = maker.connection
    #   users = connection[:users].all
    def connection
      opts = options.to_hash
      extensions = options.extensions

      conn = create_sequel_connection(opts)
      conn.extension(*extensions)
      conn
    end

    private

    # Connects with an after_connect proc that applies db_opts to every new
    # connection. The proc needs the Database, which Sequel does not pass to
    # after_connect, so it closes over +db+. Sequel hands the Database to
    # :before_preconnect before it makes any connection (preconnect, the
    # :extensions option, and the connection test all come after it), so
    # that is where +db+ is assigned.
    def create_sequel_connection(opts)
      db = nil
      user_after_connect = opts[:after_connect]
      user_before_preconnect = opts[:before_preconnect]

      opts = opts.merge(
        before_preconnect: proc do |database|
          db = database
          user_before_preconnect&.call(database)
        end,
        after_connect: proc do |conn, server|
          if user_after_connect
            user_after_connect.arity == 2 ? user_after_connect.call(conn, server) : user_after_connect.call(conn)
          end
          db.extension :db_opts
          db.db_opts.apply(conn)
        end,
      )

      if (url = opts.delete(:uri) || opts.delete(:url))
        Sequel.connect(url, opts)
      else
        Sequel.connect(opts)
      end
    end
  end
end
