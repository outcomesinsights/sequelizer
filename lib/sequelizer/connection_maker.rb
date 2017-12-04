require 'sequel'
require 'cgi'
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
      extensions = options.extensions

      conn = if url = (opts.delete(:uri) || opts.delete(:url))
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

        case opts[:adapter] && opts[:adapter].to_sym
        when :jdbc_hive2
          opts[:adapter]  = :jdbc
          auth = if realm
            ";principal=#{e principal}/#{e host_fqdn}@#{e realm}"
          elsif user
            ";user=#{e user};password=#{e password}"
          else
            ';auth=noSasl'
          end
          opts[:uri] = "jdbc:hive2://#{e opts[:host]}:#{opts.fetch(:port, 21050).to_i}/#{e(opts[:database] || 'default')}#{auth}"
        when :jdbc_impala
          opts[:adapter]  = :jdbc
          auth = if realm
            ";AuthMech=1;KrbServiceName=#{e principal};KrbAuthType=2;KrbHostFQDN=#{e host_fqdn};KrbRealm=#{e realm}"
          elsif user
            if password
              ";AuthMech=3;UID=#{e user};PWD=#{e password}"
            else
              ";AuthMech=2;UID=#{e user}"
            end
          end
          opts[:uri] = "jdbc:impala://#{e opts[:host]}:#{opts.fetch(:port, 21050).to_i}/#{e(opts[:database] || 'default')}#{auth}"
        when :jdbc_postgres
          opts[:adapter]  = :jdbc
          auth = "?user=#{user}#{"&password=#{password}" if password}" if user
          opts[:uri] = "jdbc:postgresql://#{e opts[:host]}:#{opts.fetch(:port, 5432).to_i}/#{e(opts[:database])}#{auth}"
        when :impala
          opts[:database] ||= 'default'
          opts[:port] ||= 21000
          if principal
            # realm doesn't seem to be used?
            opts[:transport] = :sasl
            opts[:sasl_params] = {
              mechanism: "GSSAPI",
              remote_host: host_fqdn,
              remote_principal: principal
            }
          end
        end

        Sequel.connect(opts)
      end
      conn.extension(*extensions)
      conn
    end

    private

    def e(v)
      CGI.escape(v.to_s)
    end
  end
end

