module Sequel
  module MakeReadyable
    def make_ready(opts = {})
      self.extension :usable
      ReadyMaker.new(self, opts).run
    end
  end

  class ReadyMaker
    attr_reader :db, :opts

    def initialize(db, opts)
      @db = db
      @opts = opts
    end
  
    def run
      if opts[:use_schema]
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
