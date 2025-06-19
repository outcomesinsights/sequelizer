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

    # Internal schema registry for managing column information across different sources.
    # This class centralizes the storage and retrieval of table/view column metadata
    # from multiple sources including created tables, views, and manually loaded schemas.
    class SchemaRegistry

      # Initialize a new schema registry for the given database.
      #
      # @param db [Sequel::Database] the database instance this registry belongs to
      def initialize(db)
        @db = db
        @created_tables = {}  # Tables created during the session
        @created_views = {}   # Views created during the session
        @schemas = {}         # Manually loaded/added schemas
      end

      # Add schema information for a table that was manually specified.
      # This method stores schemas added via add_table_schema or load_schema.
      #
      # @param name [String, Symbol] the table name
      # @param columns [Array] array of [column_name, column_info] pairs
      def add_schema(name, columns)
        Sequel.synchronize { @schemas[name.to_s] = columns }
      end

      # Record column information for a table created during the session.
      # This method is called automatically when CREATE TABLE statements are executed.
      #
      # @param name [String] the literal table name from the database
      # @param columns [Array] array of [column_name, column_info] pairs
      def add_created_table(name, columns)
        Sequel.synchronize { @created_tables[name] = columns }
      end

      # Record column information for a view created during the session.
      # This method is called automatically when CREATE VIEW statements are executed.
      #
      # @param name [String] the literal view name from the database
      # @param columns [Array] array of [column_name, column_info] pairs
      def add_created_view(name, columns)
        Sequel.synchronize { @created_views[name] = columns }
      end

      # Find column information for a given table/view name.
      # This method searches through all available registries in priority order:
      # 1. Created views (highest priority - most recent)
      # 2. Created tables (medium priority - session specific)
      # 3. Loaded schemas (lowest priority - external definitions)
      #
      # @param name [String, Symbol] the table/view name to look up
      # @return [Array<Symbol>, nil] array of column names as symbols, or nil if not found
      def find_columns(name)
        table_name = name.to_s
        literal_name = @db.literal(name)

        # Search through registries in priority order
        [@created_views, @created_tables, @schemas].each do |registry|
          next unless registry

          # Try literal representation first (most common for created tables/views)
          if (columns = Sequel.synchronize { registry[literal_name] })
            return columns.map { |c, _| c }
          end

          # Try string representation (for manually added schemas)
          if (columns = Sequel.synchronize { registry[table_name] })
            return columns.map { |c, _| c }
          end

          # Try finding by Sequel::LiteralString key (for test setup compatibility)
          registry.each_key do |key|
            if key.respond_to?(:to_s) && key.to_s == literal_name && (columns = Sequel.synchronize { registry[key] })
              return columns.map { |c, _| c }
            end
          end
        end

        nil
      end

      # Merge new schema definitions into the existing schemas registry.
      # Used when loading schemas from YAML files.
      #
      # @param new_schemas [Hash] hash of table_name => column_definitions
      def merge_schemas(new_schemas)
        Sequel.synchronize { @schemas.merge!(new_schemas) }
      end

      # Directly set the schemas registry (primarily for test setup).
      # This method replaces the entire schemas hash.
      #
      # @param schemas_hash [Hash] the new schemas hash to use
      def set_schemas(schemas_hash)
        Sequel.synchronize { @schemas = schemas_hash }
      end

    end

    # Sets up the cold column tracking when the extension is loaded
    def self.extended(db)
      db.extend_datasets(ColdColDataset)
      db.instance_variable_set(:@cold_col_registry, SchemaRegistry.new(db))
    end

    # Access the schema registry for this database instance.
    #
    # @return [SchemaRegistry] the registry managing column information
    def cold_col_registry
      @cold_col_registry
    end

    # Load table schema information from a YAML file
    def load_schema(path)
      schema_data = Psych.load_file(path) || {}
      schemas = schema_data.to_h do |table, info|
        columns = (info[:columns] || {}).map { |column_name, col_info| [column_name.to_sym, col_info] }
        [table.to_s, columns]
      end
      cold_col_registry.merge_schemas(schemas)
    end

    # Manually add schema information for a table
    def add_table_schema(name, info)
      cold_col_registry.add_schema(name, info)
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
      cold_col_registry.add_created_table(literal(name), columns)
    end

    def record_view(name, columns)
      cold_col_registry.add_created_view(literal(name), columns)
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

    # Determine the probable columns for a dataset based on its query options.
    # This is the main entry point for column determination logic.
    #
    # @param opts_chain [Hash] the dataset's query options
    # @return [Array<Symbol>] array of probable column names
    def probable_columns(opts_chain)
      cols = opts_chain[:select]

      return columns_from_sources(opts_chain) if cols.blank?

      columns_from_select_list(cols, opts_chain)
    end

    # Extract columns when no explicit SELECT list is present.
    # Returns columns from all source tables (FROM and JOIN clauses).
    #
    # @param opts_chain [Hash] the dataset's query options
    # @return [Array<Symbol>] array of column names from all sources
    def columns_from_sources(opts_chain)
      froms = opts_chain[:from] || []
      joins = (opts_chain[:join] || []).map(&:table_expr)
      (froms + joins).flat_map { |from| fetch_columns(from, opts_chain) }
    end

    # Extract columns from an explicit SELECT list.
    # Handles three types of column specifications: *, table.*, and explicit columns.
    #
    # @param cols [Array] the SELECT column expressions
    # @param opts_chain [Hash] the dataset's query options
    # @return [Array<Symbol>] array of column names from the SELECT list
    def columns_from_select_list(cols, opts_chain)
      star_columns = extract_star_columns(cols, opts_chain)
      table_star_columns = extract_table_star_columns(cols, opts_chain)
      explicit_columns = extract_explicit_columns(cols)

      (star_columns + table_star_columns + explicit_columns).flatten
    end

    # Extract columns when SELECT * is present.
    # Returns all columns from tables in the FROM clause.
    #
    # @param cols [Array] the SELECT column expressions
    # @param opts_chain [Hash] the dataset's query options
    # @return [Array<Symbol>] array of column names from FROM sources
    def extract_star_columns(cols, opts_chain)
      return [] unless select_all?(cols)

      (opts_chain[:from] || []).flat_map { |from| fetch_columns(from, opts_chain) }
    end

    # Extract columns from table.* expressions in the SELECT list.
    # Handles cases like SELECT users.*, posts.title.
    #
    # @param cols [Array] the SELECT column expressions
    # @param opts_chain [Hash] the dataset's query options
    # @return [Array<Symbol>] array of column names from table.* expressions
    def extract_table_star_columns(cols, opts_chain)
      cols.select { |c| c.is_a?(Sequel::SQL::ColumnAll) }
          .flat_map { |c| from_named_sources(c.table, opts_chain) }
    end

    # Extract explicitly named columns from the SELECT list.
    # Handles individual column references and expressions with aliases.
    #
    # @param cols [Array] the SELECT column expressions
    # @return [Array<Symbol>] array of explicit column names
    def extract_explicit_columns(cols)
      cols.reject { |c| c == WILDCARD || c.is_a?(Sequel::SQL::ColumnAll) }
          .map { |c| probable_column_name(c) }
    end

    private

    # Check if the SELECT list contains a wildcard (*) expression.
    #
    # @param cols [Array] the SELECT column expressions
    # @return [Boolean] true if SELECT * is present
    def select_all?(cols)
      cols.any? { |c| c == WILDCARD }
    end

    # Find columns for a named source (table, view, alias, or CTE).
    # This method searches through different types of named sources in order:
    # 1. Aliased FROM expressions (e.g., FROM table AS alias)
    # 2. Common Table Expressions (WITH clauses)
    # 3. Aliased JOIN expressions (e.g., JOIN table AS alias)
    # 4. Schema registry (created/loaded tables and views)
    #
    # @param name [String, Symbol] the source name to look up
    # @param opts_chain [Hash] the dataset's query options
    # @return [Array<Symbol>] array of column names for the source
    # @raise [RuntimeError] if the source cannot be found
    def from_named_sources(name, opts_chain)
      # Try aliased FROM expressions first
      if (columns = find_from_alias(name, opts_chain))
        return columns
      end

      # Try CTE (WITH clause) expressions
      if (columns = find_cte_columns(name, opts_chain))
        return columns
      end

      # Try aliased JOIN expressions
      if (columns = find_join_alias(name, opts_chain))
        return columns
      end

      # Try registry lookup (created tables/views and loaded schemas)
      if (columns = db.cold_col_registry.find_columns(name))
        return columns
      end

      raise("Failed to find columns for #{literal(name)}")
    end

    # Find columns for an aliased FROM expression.
    # Searches the FROM clause for expressions like "FROM table AS alias".
    #
    # @param name [String, Symbol] the alias name to find
    # @param opts_chain [Hash] the dataset's query options
    # @return [Array<Symbol>, nil] column names if found, nil otherwise
    def find_from_alias(name, opts_chain)
      from = (opts_chain[:from] || [])
             .select { |f| f.is_a?(Sequel::SQL::AliasedExpression) }
             .detect { |f| literal(f.alias) == literal(name) }

      from&.expression&.columns_search(opts_chain)
    end

    # Find columns for a Common Table Expression (CTE).
    # Searches up the query chain for WITH clauses that define the given name.
    #
    # @param name [String, Symbol] the CTE name to find
    # @param opts_chain [Hash] the dataset's query options
    # @return [Array<Symbol>, nil] column names if found, nil otherwise
    def find_cte_columns(name, opts_chain)
      current_opts = opts_chain

      while current_opts.present?
        with = (current_opts[:with] || []).detect { |wh| literal(wh[:name]) == literal(name) }
        return with[:dataset].columns_search(opts_chain) if with

        current_opts = current_opts[:parent_opts]
      end

      nil
    end

    # Find columns for an aliased JOIN expression.
    # Searches JOIN clauses for expressions like "JOIN table AS alias".
    #
    # @param name [String, Symbol] the join alias name to find
    # @param opts_chain [Hash] the dataset's query options
    # @return [Array<Symbol>, nil] column names if found, nil otherwise
    def find_join_alias(name, opts_chain)
      join = (opts_chain[:join] || []).detect { |jc| literal(jc.table_expr.try(:alias)) == literal(name) }
      return nil unless join

      join_expr = join.table_expr.expression
      return join_expr.columns_search(opts_chain) if join_expr.is_a?(Sequel::Dataset)

      # If it's a table reference, look it up in the registry
      db.cold_col_registry.find_columns(join_expr)
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
