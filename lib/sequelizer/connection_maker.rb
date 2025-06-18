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

      conn = if (url = opts.delete(:uri) || opts.delete(:url))
               Sequel.connect(url, opts)
             else
               # Kerberos related options
               realm = opts[:realm]
               host_fqdn = opts[:host_fqdn] || opts[:host]
               principal = opts[:principal]

               adapter = opts[:adapter]
               if adapter =~ /\Ajdbc_/
                 user = opts[:user]
                 password = opts[:password]
               end

               case opts[:adapter]&.to_sym
               when :jdbc_hive2
                 opts[:adapter] = :jdbc
                 auth = if realm
                          ";principal=#{e principal}/#{e host_fqdn}@#{e realm}"
                        elsif user
                          ";user=#{e user};password=#{e password}"
                        else
                          ';auth=noSasl'
                        end
                 opts[:uri] =
                   "jdbc:hive2://#{e opts[:host]}:#{opts.fetch(:port,
                                                               21_050).to_i}/#{e(opts[:database] || "default")}#{auth}"
               when :jdbc_impala
                 opts[:adapter] = :jdbc
                 auth = if realm
                          ";AuthMech=1;KrbServiceName=#{e principal};KrbAuthType=2;KrbHostFQDN=#{e host_fqdn};KrbRealm=#{e realm}"
                        elsif user
                          if password
                            ";AuthMech=3;UID=#{e user};PWD=#{e password}"
                          else
                            ";AuthMech=2;UID=#{e user}"
                          end
                        end
                 opts[:uri] =
                   "jdbc:impala://#{e opts[:host]}:#{opts.fetch(:port,
                                                                21_050).to_i}/#{e(opts[:database] || "default")}#{auth}"
               when :jdbc_postgres
                 opts[:adapter] = :jdbc
                 auth = "?user=#{user}#{"&password=#{password}" if password}" if user
                 opts[:uri] =
                   "jdbc:postgresql://#{e opts[:host]}:#{opts.fetch(:port, 5432).to_i}/#{e(opts[:database])}#{auth}"
               when :impala
                 opts[:database] ||= 'default'
                 opts[:port] ||= 21_000
                 if principal
                   # realm doesn't seem to be used?
                   opts[:transport] = :sasl
                   opts[:sasl_params] = {
                     mechanism: 'GSSAPI',
                     remote_host: host_fqdn,
                     remote_principal: principal,
                   }
                 end
               end

               Sequel.connect(opts)
             end
      conn.extension(*extensions)
      conn
    end

    private

    # URL-escapes a value for safe inclusion in database connection strings.
    #
    # @param v [Object] the value to escape
    # @return [String] the URL-escaped string
    def e(v)
      CGI.escape(v.to_s)
    end

  end
end
