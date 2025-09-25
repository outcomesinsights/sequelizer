require 'sequel'
require 'cgi'
require_relative 'options'

module Sequelizer
  # = ConnectionMaker
  #
  # Class that handles loading/interpreting the database options and
  # creates the Sequel connection. This class is responsible for:
  #
  # * Loading configuration from multiple sources
  # * Handling adapter-specific connection logic
  # * Supporting various database types including PostgreSQL, Impala, and Hive2
  # * Managing Kerberos authentication for enterprise databases
  #
  # @example Basic usage
  #   maker = ConnectionMaker.new(adapter: 'postgres', host: 'localhost')
  #   db = maker.connection
  #
  # @example With Kerberos authentication
  #   maker = ConnectionMaker.new(
  #     adapter: 'jdbc_hive2',
  #     host: 'hive.example.com',
  #     realm: 'EXAMPLE.COM',
  #     principal: 'hive'
  #   )
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
    # @option options [String] :adapter database adapter (e.g., 'postgres', 'jdbc_hive2')
    # @option options [String] :host database host
    # @option options [Integer] :port database port
    # @option options [String] :database database name
    # @option options [String] :username database username
    # @option options [String] :password database password
    # @option options [String] :search_path PostgreSQL schema search path
    # @option options [String] :realm Kerberos realm for authentication
    # @option options [String] :principal Kerberos principal name
    def initialize(options = nil)
      @options = Options.new(options)
    end

    # Returns a Sequel connection to the database.
    #
    # This method handles adapter-specific connection logic including:
    # * Standard Sequel adapters
    # * JDBC-based connections (Hive2, Impala, PostgreSQL)
    # * Kerberos authentication
    # * PostgreSQL schema management
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
      case opts[:adapter]&.to_sym
      when :jdbc_hive2
        configure_jdbc_hive2(opts)
      when :jdbc_impala
        configure_jdbc_impala(opts)
      when :jdbc_postgres
        configure_jdbc_postgres(opts)
      when :impala
        configure_impala(opts)
      end
    end

    def configure_jdbc_hive2(opts)
      opts[:adapter] = :jdbc
      auth = build_hive2_auth_string(opts)
      port = opts.fetch(:port, 21_050).to_i
      database = opts[:database] || 'default'
      opts[:uri] = "jdbc:hive2://#{e opts[:host]}:#{port}/#{e database}#{auth}"
    end

    def configure_jdbc_impala(opts)
      opts[:adapter] = :jdbc
      auth = build_impala_auth_string(opts)
      port = opts.fetch(:port, 21_050).to_i
      database = opts[:database] || 'default'
      opts[:uri] = "jdbc:impala://#{e opts[:host]}:#{port}/#{e database}#{auth}"
    end

    def configure_jdbc_postgres(opts)
      opts[:adapter] = :jdbc
      auth = build_postgres_auth_string(opts)
      port = opts.fetch(:port, 5432).to_i
      opts[:uri] = "jdbc:postgresql://#{e opts[:host]}:#{port}/#{e opts[:database]}#{auth}"
    end

    def configure_impala(opts)
      opts[:database] ||= 'default'
      opts[:port] ||= 21_000
      setup_impala_sasl_if_needed(opts)
    end

    def build_hive2_auth_string(opts)
      realm = opts[:realm]
      host_fqdn = opts[:host_fqdn] || opts[:host]
      principal = opts[:principal]
      user = opts[:user]
      password = opts[:password]

      if realm
        ";principal=#{e principal}/#{e host_fqdn}@#{e realm}"
      elsif user
        ";user=#{e user};password=#{e password}"
      else
        ';auth=noSasl'
      end
    end

    def build_impala_auth_string(opts)
      realm = opts[:realm]
      host_fqdn = opts[:host_fqdn] || opts[:host]
      principal = opts[:principal]
      user = opts[:user]
      password = opts[:password]

      if realm
        ";AuthMech=1;KrbServiceName=#{e principal};KrbAuthType=2;" \
          "KrbHostFQDN=#{e host_fqdn};KrbRealm=#{e realm}"
      elsif user
        if password
          ";AuthMech=3;UID=#{e user};PWD=#{e password}"
        else
          ";AuthMech=2;UID=#{e user}"
        end
      end
    end

    def build_postgres_auth_string(opts)
      user = opts[:user]
      password = opts[:password]
      return unless user

      "?user=#{user}#{"&password=#{password}" if password}"
    end

    def setup_impala_sasl_if_needed(opts)
      principal = opts[:principal]
      host_fqdn = opts[:host_fqdn] || opts[:host]
      return unless principal

      opts[:transport] = :sasl
      opts[:sasl_params] = {
        mechanism: 'GSSAPI',
        remote_host: host_fqdn,
        remote_principal: principal,
      }
    end

    # URL-escapes a value for safe inclusion in database connection strings.
    #
    # @param v [Object] the value to escape
    # @return [String] the URL-escaped string
    def e(v)
      CGI.escape(v.to_s)
    end

  end
end
