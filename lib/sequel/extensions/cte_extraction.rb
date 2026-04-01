# frozen_string_literal: true

#
# The cte_extraction extension extracts Common Table Expressions (CTEs) from
# nested Sequel datasets and materializes them as temporary tables or
# re-attaches them as WITH clauses, depending on platform capabilities.
#
#   DB.extension :platform, :cte_extraction
#
#   ds = DB[:patients]
#     .with(:cohort, DB[:visits].where(type: 'inpatient'))
#     .where(id: DB[:cohort].select(:patient_id))
#
#   ds.with_cte_extraction
#   # => extracts CTEs and either:
#   #    - re-adds as WITH clauses (platform prefers CTEs)
#   #    - materializes as temp tables (platform supports temp tables)
#   #    - materializes in interim schema (fallback)
#
# Ported from ConceptQL's Scope class CTE extraction logic.
#
# Related module: Sequel::CteExtraction

module Sequel

  module CteExtraction

    # AST transformer that intercepts Dataset nodes within expressions
    # (e.g., subqueries in WHERE clauses) and delegates them to the
    # Extractor for CTE extraction.
    class AstExtractor < Sequel::ASTTransformer

      def initialize(extractor)
        super()
        @extractor = extractor
      end

      private

      def v(o)
        if o.is_a?(Sequel::Dataset)
          @extractor.recursive_extract_ctes(o)
        else
          super
        end
      end

    end

    # Manages CTE extraction state: walks a dataset tree, collects CTEs
    # into an array, and returns a cleaned dataset with CTEs removed.
    class Extractor

      attr_reader :ctes

      def initialize
        @ctes = []
      end

      # Recursively extract CTEs from a dataset.
      #
      # Walks through WITH, FROM, JOIN, compound (UNION/INTERSECT/EXCEPT),
      # and WHERE clauses to find and extract nested datasets.
      #
      # @param query [Sequel::Dataset] the dataset to extract from
      # @return [Sequel::Dataset] the cleaned dataset with CTEs removed
      def recursive_extract_ctes(query)
        query = extract_with_clauses(query)
        query = extract_from_clauses(query)
        query = extract_join_clauses(query)
        query = extract_compound_clauses(query)
        extract_where_clauses(query)
      end

      # Sort extracted CTEs in topological (dependency) order.
      #
      # @return [Array<Array>] sorted CTEs as [name, dataset, opts] triples
      def sorted_ctes
        unique = @ctes.uniq(&:first)

        deps = unique.each_with_object({}) do |(name, ds), memo|
          sql = ds.sql
          memo[name] = unique.filter_map do |(other_name, _)|
            next if other_name == name

            other_name if sql.include?(%("#{other_name}"))
          end
        end

        topological_sort([], unique, deps)
      end

      # Extract a table expression from FROM or JOIN clauses.
      #
      # @param expr [Object] a table expression (Dataset, AliasedExpression, or other)
      # @return [Object] the expression with nested Datasets extracted
      def extract_cte_expr(expr)
        case expr
        when Sequel::Dataset
          recursive_extract_ctes(expr)
        when Sequel::SQL::AliasedExpression
          if expr.expression.is_a?(Sequel::Dataset)
            Sequel.as(recursive_extract_ctes(expr.expression), expr.alias)
          else
            expr
          end
        else
          expr
        end
      end

      private

      def extract_with_clauses(query)
        with = query.opts[:with]
        return query unless with

        keep, remove = with.partition { |w| w[:no_temp_table] }
        @ctes.concat(remove.map do |w|
          opts = w.except(:name, :dataset, :no_temp_table)
          [w[:name], recursive_extract_ctes(w[:dataset]), opts]
        end)
        query.clone(with: keep.empty? ? nil : keep)
      end

      def extract_from_clauses(query)
        from = query.opts[:from]
        return query unless from

        query.clone(from: from.map { |t| extract_cte_expr(t) })
      end

      def extract_join_clauses(query)
        joins = query.opts[:join]
        return query unless joins

        query.clone(join: joins.map do |jc|
          jc.class.new(jc.on, jc.join_type, extract_cte_expr(jc.table_expr))
        end)
      end

      def extract_compound_clauses(query)
        compounds = query.opts[:compounds]
        return query unless compounds

        query.clone(compounds: compounds.map { |t, ds, a| [t, recursive_extract_ctes(ds), a] })
      end

      def extract_where_clauses(query)
        where = query.opts[:where]
        return query unless where

        query.clone(where: AstExtractor.new(self).transform(where))
      end

      def topological_sort(sorted, unsorted, deps)
        return sorted if unsorted.empty?

        add, unsorted = unsorted.partition { |label, _| deps[label].empty? }
        sorted += add

        sorted_names = sorted.map(&:first)
        new_deps = deps.each_with_object({}) do |(label, dps), memo|
          memo[label] = dps - sorted_names
        end

        topological_sort(sorted, unsorted, new_deps)
      end

    end

    # Wraps a cleaned dataset and its extracted CTEs, materializing them
    # as temporary tables (or interim-schema tables) around query execution.
    class TempTableExecutor

      attr_reader :dataset, :ctes, :db

      # @param dataset [Sequel::Dataset] the cleaned dataset (CTEs removed)
      # @param ctes [Array<Array>] sorted [name, dataset, opts] triples
      # @param db [Sequel::Database] database connection
      # @param options [Hash] platform-specific options
      # @option options [Symbol, String, nil] :interim_schema schema for non-temp-table platforms
      # @option options [String, nil] :interim_prefix table name prefix for interim tables
      # @option options [Boolean] :drop_table_needs_unquoted whether DROP TABLE needs unquoted names
      def initialize(dataset, ctes, db, **options)
        @dataset = dataset
        @ctes = ctes
        @db = db
        @interim_schema = options[:interim_schema]
        @interim_prefix = options[:interim_prefix]
        @drop_table_needs_unquoted = options[:drop_table_needs_unquoted] || false
      end

      # Returns a dataset extended with lazy temp-table creation/cleanup.
      #
      # On first iteration (each/to_hash/to_hash_groups), creates temp
      # tables for all extracted CTEs, runs the query, then drops them
      # in reverse order via ensure.
      #
      # @return [Sequel::Dataset] the extended dataset
      def to_dataset
        @dataset.with_extend(build_extension_module)
      end

      private

      def build_extension_module
        ctes = @ctes
        executor = self

        build_iteration_module(ctes, executor).tap do |mod|
          mod.define_method(:sql_statements) do
            ctes.map { |name, ds, _| [name, ds.sql] }.push([:query, sql]).to_h
          end
          mod.define_method(:drop_temp_tables) { executor.send(:drop_tables) }
        end
      end

      # Override each/to_hash/to_hash_groups to lazily create/drop
      # temp tables. Must override all three when sequel_pg is in use.
      def build_iteration_module(ctes, executor)
        Module.new do
          %i[each to_hash_groups to_hash].each do |meth|
            define_method(meth) do |*args, &block|
              if !ctes.empty? && !opts[:cte_extraction_tables_created]
                begin
                  executor.send(:create_tables)
                  clone(cte_extraction_tables_created: true).send(meth, *args, &block)
                ensure
                  executor.send(:drop_tables)
                end
              else
                super(*args, &block)
              end
            end
          end
        end
      end

      # Create materialized tables for all extracted CTEs.
      def create_tables
        @ctes.each do |name, ds, _opts|
          qualified = qualify_table_name(name)
          create_opts = build_create_options(ds)
          @db.create_table(qualified, create_opts)
        end
      end

      # Drop materialized tables in reverse dependency order.
      def drop_tables
        table_names = @ctes.reverse_each.map { |name, _, _| qualify_table_name(name) }
        table_names = table_names.map { |n| unquote(n) } if @drop_table_needs_unquoted

        @db.drop_table?(*table_names) unless table_names.empty?
      rescue Sequel::DatabaseError
        # Best-effort cleanup; warn but don't raise during ensure
        warn("cte_extraction: unable to drop tables: #{table_names}")
      end

      def qualify_table_name(name)
        if @interim_schema
          prefixed = @interim_prefix ? :"#{@interim_prefix}#{name}" : name
          Sequel.qualify(@interim_schema, prefixed)
        else
          name
        end
      end

      def build_create_options(ds)
        if @interim_schema
          { as: ds }
        else
          { temp: true, as: ds }
        end
      end

      def unquote(name)
        case name
        when Sequel::SQL::QualifiedIdentifier
          Sequel.lit("#{name.table}.#{name.column}")
        else
          Sequel.lit(name.to_s)
        end
      end

    end

    # Dataset methods added when the extension is loaded.
    module DatasetMethods

      # Extract CTEs from this dataset and return a new dataset that
      # materializes them according to the platform's capabilities.
      #
      # @return [Sequel::Dataset] a dataset with CTEs extracted and
      #   re-attached (as WITH clauses or temp tables)
      def with_cte_extraction
        extractor = Extractor.new
        cleaned = extractor.recursive_extract_ctes(self)
        sorted = extractor.sorted_ctes

        return cleaned if sorted.empty?

        platform = db.respond_to?(:platform) ? db.platform : nil

        if platform.nil? || platform.prefers?(:cte)
          reattach_as_with(cleaned, sorted)
        else
          build_temp_table_executor(cleaned, sorted, platform).to_dataset
        end
      end

      private

      def reattach_as_with(dataset, ctes)
        ctes.each do |name, ds, with_opts|
          dataset = if with_opts.nil? || with_opts.empty?
                      dataset.with(name, ds)
                    else
                      dataset.with(name, ds, with_opts)
                    end
        end
        dataset
      end

      def build_temp_table_executor(dataset, ctes, platform)
        opts = {}
        unless platform.supports?(:temp_tables)
          opts[:interim_schema] = platform[:interim_schema]
          opts[:interim_prefix] = platform[:interim_prefix]
        end
        opts[:drop_table_needs_unquoted] = platform[:drop_table_needs_unquoted] || false

        TempTableExecutor.new(dataset, ctes, db, **opts)
      end

    end

    def self.extended(db)
      db.extend_datasets(DatasetMethods)
    end

  end

  Database.register_extension(:cte_extraction, CteExtraction)

end
