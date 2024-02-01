module Sequel
  module MakeReadyable
    ##
    # This method is primarily geared towards Spark SQL-based databases.
    #
    # Given some options, prepares a set of views to represent a set
    # of tables across a collection of different schemas and external,
    # unmanaged tables.
    #
    #   DB.make_ready(use_schema: :schema)
    #   # => USE `schema`
    #
    # When using search_path, tables from previous schema override tables
    # from the next schema.  This is analogous to the way Unix searches 
    # the PATH variable for programs.
    #
    # Assuming the following tables: schema1.a, schema2.a, schema2.b
    #
    #   DB.make_ready(search_path: [:schema1, :schema2])
    #   # => CREATE TEMPORARY VIEW `a` AS SELECT * FROM `schema1`.`a;`
    #   # => CREATE TEMPORARY VIEW `b` AS SELECT * FROM `schema2`.`b;`
    #
    # When using Pathnames, the extension on the file becomes the format
    # to try to read from the file.  
    #
    #   DB.make_ready(search_path: [Pathname.new("c.parquet"), Pathname.new("d.orc")])
    #   # => CREATE TEMPORARY VIEW `c` USING parquet OPTIONS ('path'='c.parquet')
    #   # => CREATE TEMPORARY VIEW `d` USING orc OPTIONS ('path'='d.orc')
    #
    # @param [Hash] opts the options used to prepare the database
    # @option opts [String] :use_schema The schema to be used as the primary schema
    # @option opts [Array] :search_path A set of sympbols (to represent schemas) or Pathnames (to represent externally managed data files)
    def make_ready(opts = {})
      ReadyMaker.new(self, opts).run
    end
  end

  private 
  class ReadyMaker
    attr_reader :db, :opts

    def initialize(db, opts)
      @db = db
      @opts = opts
    end
  
    def run
      if opts[:use_schema]
        db.extension :usable
        db.use(opts[:use_schema])
      end
      only_tables = Array(opts[:only])
      created_views = (Array(opts[:except]) || [])
      (opts[:search_path] || []).each do |schema|
        source = get_source(db, schema)
        tables = source.tables(schema: schema) - created_views
        tables &= only_tables unless only_tables.empty?
        tables.each do |table|
          create_view(source, table, schema)
          created_views << table
        end
      end
    end

    def create_view(source, table, schema)
      if schema.to_s =~ %r{/}
        source.create_view(table, temp: true)
      else
        source.create_view(table, db[Sequel.qualify(schema, table)], temp: true)
      end
    end

    def get_source(db, schema)
      if schema.to_s =~ %r{/}
        FileSourcerer.new(db, Pathname.new(schema))
      else
        db
      end
    end

    class FileSourcerer
      attr_reader :db, :schema
      def initialize(db, schema)
        @db = db
        @schema = schema
      end

      def tables(opts = {})
        [schema.basename(".*").to_s.to_sym]
      end

      def create_view(table, opts = {})
        db.create_view(table, {
          temp: true,
          using: format,
          options: { path: schema.expand_path }
        }.merge(opts))
      end

      def format
        schema.extname[1..-1]
      end
    end
  end

  Database.register_extension(:make_readyable, MakeReadyable)
end
