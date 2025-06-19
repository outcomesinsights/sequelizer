# frozen_string_literal: true

#
# The cold_col extension adds support for determining dataset column information
# without executing queries against a live database. This "cold column" functionality
# is useful for testing, development, and static analysis scenarios where
# database connections may not be available or desirable.
#
# The extension maintains schema information through three sources:
# - Pre-loaded schemas from YAML files via load_schema
# - Automatically recorded tables/views created during the session
# - Manually added table schemas via add_table_schema
#
# Basic usage:
#
#   db = Sequel.mock.extension(:cold_col)
#
#   # Load schema from YAML file
#   db.load_schema('schemas.yml')
#
#   # Or add schema manually
#   db.add_table_schema(:users, [[:id, {}], [:name, {}], [:email, {}]])
#
#   # Now datasets can determine columns without database queries
#   ds = db[:users].select(:name, :email)
#   ds.columns  # => [:name, :email]
#
# The extension supports complex queries including JOINs, CTEs, subqueries,
# and aliased tables. Schema YAML files should follow this format:
#
#   users:
#     columns:
#       id: { type: integer, primary_key: true }
#       name: { type: string }
#       email: { type: string }
#
# You can load the extension into the database using:
#
#   DB.extension :cold_col

require 'active_support/core_ext/object/try'
require 'active_support/core_ext/object/blank'

module Sequel

  module ColdColDatabase

    # Sets up the cold column tracking when the extension is loaded
    def self.extended(db)
      db.extend_datasets(ColdColDataset)
      db.instance_variable_set(:@created_tables, {})
      db.instance_variable_set(:@created_views, {})
      db.instance_variable_set(:@schemas, {})
    end

    # Load table schema information from a YAML file
    def load_schema(path)
      schema_data = Psych.load_file(path) || {}
      schemas = schema_data.to_h do |table, info|
        columns = (info[:columns] || {}).map { |column_name, col_info| [column_name.to_sym, col_info] }
        [table.to_s, columns]
      end
      schemas = (instance_variable_get(:@schemas) || {}).merge(schemas)
      instance_variable_set(:@schemas, schemas)
    end

    # Manually add schema information for a table
    def add_table_schema(name, info)
      schemas = instance_variable_get(:@schemas) || {}
      schemas[name.to_s] = info
      instance_variable_set(:@schemas, schemas)
    end

    def create_table_as(name, sql, options = {})
      super.tap do |_|
        record_table(name, columns_from_sql(sql))
      end
    end

    def create_table_from_generator(name, generator, options)
      super.tap do |_|
        record_table(name, columns_from_generator(generator))
      end
    end

    def create_table_sql(name, generator, options)
      super.tap do |_|
        record_table(name, columns_from_generator(generator))
      end
    end

    def create_view_sql(name, source, options)
      super.tap do |_|
        record_view(name, columns_from_sql(source)) unless options[:dont_record]
      end
    end

    def record_table(name, columns)
      name = literal(name)
      Sequel.synchronize { @created_tables[name] = columns }
    end

    def record_view(name, columns)
      name = literal(name)
      # puts "recording view #{name}"
      Sequel.synchronize { @created_views[name] = columns }
    end

    def columns_from_sql(sql)
      sql.columns
    end

    def columns_from_generator(generator)
      generator.columns.map { |c| [c[:name], c] }
    end

  end

  module ColdColDataset

    # Return the columns for the dataset without executing a query
    def columns
      columns_search
    end

    def columns_search(opts_chain = nil)
      if (cols = _columns)
        return cols
      end

      unless (pcs = probable_columns(opts.merge(parent_opts: opts_chain))) && pcs.all?
        raise("Failed to find columns for #{sql}")
      end

      self.columns = pcs
    end

    protected

    WILDCARD = Sequel.lit('*').freeze

    def probable_columns(opts_chain)
      if (cols = opts[:select]).blank?
        froms = opts[:from] || []
        joins = (opts[:join] || []).map(&:table_expr)
        (froms + joins).flat_map { |from| fetch_columns(from, opts_chain) }
      else
        from_stars = []

        if select_all?(cols)
          from_stars = (opts[:from] || []).flat_map { |from| fetch_columns(from, opts_chain) }
          cols = cols.reject { |c| c == WILDCARD }
        end

        from_stars += cols
                      .select { |c| c.is_a?(Sequel::SQL::ColumnAll) }
                      .flat_map { |c| from_named_sources(c.table, opts_chain) }

        cols = cols.reject { |c| c.is_a?(Sequel::SQL::ColumnAll) }

        (from_stars + cols.map { |c| probable_column_name(c) }).flatten
      end
    end

    private

    def select_all?(cols)
      cols.any? { |c| c == WILDCARD }
    end

    def from_named_sources(name, opts_chain)
      current_opts = opts_chain

      from = (opts[:from] || [])
             .select { |f| f.is_a?(Sequel::SQL::AliasedExpression) }
             .detect { |f| literal(f.alias) == literal(name) }

      return from.expression.columns_search(opts_chain) if from

      with = nil

      while current_opts.present? && with.blank?
        with = (current_opts[:with] || []).detect { |wh| literal(wh[:name]) == literal(name) }
        current_opts = current_opts[:parent_opts]
      end

      return with[:dataset].columns_search(opts_chain) if with

      if (join = (opts[:join] || []).detect { |jc| literal(jc.table_expr.try(:alias)) == literal(name) })
        join_expr = join.table_expr.expression
        return join_expr.columns_search(opts_chain) if join_expr.is_a?(Sequel::Dataset)

        name = join_expr
      end

      created_views = db.instance_variable_get(:@created_views) || {}
      created_tables = db.instance_variable_get(:@created_tables) || {}
      schemas = db.instance_variable_get(:@schemas) || {}
      [created_views, created_tables, schemas].each do |known_columns|
        if known_columns && (table = literal(name)) && (sch = Sequel.synchronize { known_columns[table] })
          return sch.map { |c, _| c }
        end
      end

      # Try with string representation for manually added schemas
      if schemas && (sch = Sequel.synchronize { schemas[name.to_s] })
        return sch.map { |c, _| c }
      end

      raise("Failed to find columns for #{literal(name)}")
    end

    def fetch_columns(from, opts_chain)
      from = from.expression if from.is_a?(SQL::AliasedExpression)

      case from
      when Dataset
        from.columns_search(opts_chain)
      when Symbol, SQL::Identifier, SQL::QualifiedIdentifier
        from_named_sources(from, opts_chain)
      end
    end

    # Return the probable name of the column, or nil if one
    # cannot be determined.
    def probable_column_name(c)
      case c
      when Symbol
        _, c, a = split_symbol(c)
        (a || c).to_sym
      when SQL::Identifier
        c.value.to_sym
      when SQL::QualifiedIdentifier
        c.column.to_sym
      when SQL::AliasedExpression
        a = c.alias
        a.is_a?(SQL::Identifier) ? a.value.to_sym : a.to_sym
      end
    end

  end

  Database.register_extension(:cold_col, Sequel::ColdColDatabase)

end
