module Sequel

  # = DbOpts
  #
  # Sequel extension that provides database-specific options handling.
  # This extension allows setting database-specific configuration options
  # that get applied during connection establishment.
  #
  # The extension looks for options in the database configuration that match
  # the pattern `{database_type}_db_opt_{option_name}` and converts them to
  # appropriate SQL SET statements.
  #
  # @example
  #   # For PostgreSQL, options like:
  #   postgres_db_opt_work_mem: '256MB'
  #   postgres_db_opt_shared_preload_libraries: 'pg_stat_statements'
  #
  #   # Will generate:
  #   SET work_mem='256MB'
  #   SET shared_preload_libraries='pg_stat_statements'
  module DbOpts

    # Handles extraction and application of database-specific options.
    class DbOptions

      # @!attribute [r] db
      #   @return [Sequel::Database] the database instance
      attr_reader :db

      # Creates a new DbOptions instance for the given database.
      #
      # @param db [Sequel::Database] the database to configure
      def initialize(db)
        db.extension :settable
        @db = db
      end

      # Returns a hash of database-specific options extracted from the database configuration.
      #
      # @return [Hash] hash of option names to values
      def to_hash
        @_to_hash ||= extract_db_opts
      end

      # Extracts database-specific options from the database configuration.
      #
      # Looks for options matching the pattern `{database_type}_db_opt_{option_name}`
      # and extracts the option name and value.
      #
      # @return [Hash] extracted options with symbolic keys
      def extract_db_opts
        opt_regexp = /^#{db.database_type}_db_opt_/i

        db.opts.select do |k, _|
          k.to_s.match(opt_regexp)
        end.to_h { |k, v| [k.to_s.gsub(opt_regexp, '').to_sym, prep_value(k, v)] }
      end

      # Applies the database options to the given connection.
      #
      # Executes the SQL statements generated from the options on the connection.
      #
      # @param c [Object] the database connection
      def apply(c)
        sql_statements.each do |stmt|
          db.send(:log_connection_execute, c, stmt)
        end
      end

      # Prepares a value for use in SQL statements.
      #
      # Values containing non-word characters are treated as literals and quoted,
      # while simple values are used as-is.
      #
      # @param _k [Symbol] the option key (unused)
      # @param v [Object] the option value
      # @return [String] the prepared value
      def prep_value(_k, v)
        v =~ /\W/ ? db.literal(v.to_s) : v
      end

      # Generates SQL SET statements for the database options.
      #
      # @return [Array<String>] array of SQL SET statements
      def sql_statements
        db.send(:set_sql, to_hash)
      end

    end

    # Returns a DbOptions instance for this database.
    #
    # @return [DbOptions] the database options handler
    def db_opts
      @db_opts ||= DbOptions.new(self)
    end

  end

  Database.register_extension(:db_opts, DbOpts)

end
