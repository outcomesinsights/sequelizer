require 'sequel'
require_relative 'options'

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
    # @param options [Hash, nil] database connection options
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

    def create_sequel_connection(opts)
      if (url = opts.delete(:uri) || opts.delete(:url))
        Sequel.connect(url, opts)
      else
        configure_adapter_specific_options(opts)
        Sequel.connect(opts)
      end
    end

    def configure_adapter_specific_options(opts)
      # No adapter-specific configuration needed currently
    end

  end
end
