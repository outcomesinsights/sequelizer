require 'pathname'

module Sequel

  # = MakeReadyable
  #
  # Sequel extension that provides database readiness functionality,
  # primarily geared towards Spark SQL-based databases. This extension
  # allows setting up temporary views and schema configurations to prepare
  # a database for use.
  #
  # @example Basic schema usage
  #   db.extension :make_readyable
  #   db.make_ready(use_schema: :my_schema)
  #
  # @example Search path with schema precedence
  #   db.make_ready(search_path: [:schema1, :schema2])
  #
  # @example External file sources
  #   db.make_ready(search_path: [Pathname.new('data.parquet')])
  module MakeReadyable

    # Prepares the database by setting up schemas, views, and external data sources.
    #
    # This method is primarily geared towards Spark SQL-based databases.
    # Given some options, prepares a set of views to represent a set
    # of tables across a collection of different schemas and external,
    # unmanaged tables.
    #
    # @param opts [Hash] the options used to prepare the database
    # @option opts [Symbol] :use_schema The schema to be used as the primary schema
    # @option opts [Array] :search_path A set of symbols (schemas) or Pathnames (external files)
    # @option opts [Array] :only Limit view creation to these tables only
    # @option opts [Array] :except Skip view creation for these tables
    #
    # @example Set primary schema
    #   DB.make_ready(use_schema: :schema)
    #   # => USE `schema`
    #
    # @example Search path with precedence
    #   # Assuming tables: schema1.a, schema2.a, schema2.b
    #   DB.make_ready(search_path: [:schema1, :schema2])
    #   # => CREATE TEMPORARY VIEW `a` AS SELECT * FROM `schema1`.`a;`
    #   # => CREATE TEMPORARY VIEW `b` AS SELECT * FROM `schema2`.`b;`
    #
    # @example External file sources
    #   DB.make_ready(search_path: [Pathname.new("c.parquet"), Pathname.new("d.orc")])
    #   # => CREATE TEMPORARY VIEW `c` USING parquet OPTIONS ('path'='c.parquet')
    #   # => CREATE TEMPORARY VIEW `d` USING orc OPTIONS ('path'='d.orc')
    def make_ready(opts = {})
      ReadyMaker.new(self, opts).run
    end

  end

  # = ReadyMaker
  #
  # Internal class that handles the actual database preparation logic.
  # This class processes the make_ready options and executes the necessary
  # SQL statements to set up schemas, views, and external data sources.
  class ReadyMaker

    # @!attribute [r] db
    #   @return [Sequel::Database] the database instance
    # @!attribute [r] opts
    #   @return [Hash] the preparation options
    attr_reader :db, :opts

    # Creates a new ReadyMaker instance.
    #
    # @param db [Sequel::Database] the database to prepare
    # @param opts [Hash] the preparation options
    def initialize(db, opts)
      @db = db
      @opts = opts
    end

    # Executes the database preparation process.
    #
    # This method handles:
    # 1. Setting the primary schema if specified
    # 2. Processing the search path to create views
    # 3. Handling table filtering (only/except options)
    def run
      if opts[:use_schema]
        db.extension :usable
        db.use(opts[:use_schema])
      end
      only_tables = Array(opts[:only])
      created_views = Array(opts[:except]) || []
      (opts[:search_path] || []).flatten.each do |schema|
        schema = schema.to_sym unless schema.is_a?(Pathname)
        source = get_source(db, schema)
        tables = if schema.is_a?(Pathname)
                   source.tables - created_views
                 else
                   source.tables(schema: schema) - created_views
                 end
        tables &= only_tables unless only_tables.empty?
        tables.each do |table|
          create_view(source, table, schema)
          created_views << table
        end
      end
    end

    # Creates a temporary view for the given table.
    #
    # @param source [Object] the source (database or FileSourcerer)
    # @param table [Symbol] the table name
    # @param schema [Symbol, Pathname] the schema or file path
    def create_view(source, table, schema)
      if schema.to_s =~ %r{/}
        source.create_view(table, temp: true)
      else
        # For schema-based tables, just create temporary views
        # This extension is primarily for Spark SQL-based databases
        source.create_view(table, db[Sequel.qualify(schema, table)], temp: true)
      end
    end

    # Gets the appropriate source handler for the schema.
    #
    # @param db [Sequel::Database] the database instance
    # @param schema [Symbol, Pathname] the schema or file path
    # @return [Sequel::Database, FileSourcerer] the source handler
    def get_source(db, schema)
      if schema.to_s =~ %r{/}
        FileSourcerer.new(db, Pathname.new(schema.to_s))
      else
        db
      end
    end

    # = FileSourcerer
    #
    # Handles external file sources for the make_ready functionality.
    # This class creates temporary views that read from external files
    # like Parquet, ORC, etc.
    class FileSourcerer

      # @!attribute [r] db
      #   @return [Sequel::Database] the database instance
      # @!attribute [r] schema
      #   @return [Pathname] the file path
      attr_reader :db, :schema

      # Creates a new FileSourcerer instance.
      #
      # @param db [Sequel::Database] the database instance
      # @param schema [Pathname] the file path
      def initialize(db, schema)
        @db = db
        @schema = schema
      end

      # Returns the table name derived from the file name.
      #
      # @param _opts [Hash] unused options parameter
      # @return [Array<Symbol>] array containing the table name
      def tables(_opts = {})
        [schema.basename(schema.extname).to_s.to_sym]
      end

      # Creates a temporary view that reads from the external file.
      #
      # @param table [Symbol] the table/view name
      # @param opts [Hash] additional options to merge
      def create_view(table, opts = {})
        case db.database_type
        when :spark
          # Spark SQL uses USING clause for external tables
          db.create_view(table, {
            temp: true,
            using: format,
            options: { path: schema.expand_path },
          }.merge(opts))
        when :duckdb
          # DuckDB uses direct file reading with read_* functions
          create_duckdb_view(table, opts)
        else
          raise Sequel::Error, "External file sources are not supported on #{db.database_type}"
        end
      end

      private

      # Creates a view for DuckDB to read external files
      #
      # @param table [Symbol] the table/view name
      # @param _opts [Hash] additional options to merge (currently unused for DuckDB)
      def create_duckdb_view(table, _opts)
        file_path = if schema.directory?
                      schema.expand_path.join('**').join("*.#{format}").to_s
                    else
                      schema.expand_path.to_s
                    end
        read_function = case format
                        when 'parquet'
                          :read_parquet
                        when 'csv'
                          :read_csv_auto
                        when 'json'
                          :read_json_auto
                        else
                          raise Sequel::Error, "Unsupported file format '#{format}' for DuckDB"
                        end

        # DuckDB doesn't support TEMPORARY views, use regular CREATE VIEW
        db.create_view(table, db.from(Sequel.function(read_function, file_path)))
      end

      # Returns the file format based on the file extension.
      #
      # @return [String] the file format (e.g., 'parquet', 'orc')
      def format
        schema.extname[1..]
      end

    end

  end

  Database.register_extension(:make_readyable, MakeReadyable)

end
