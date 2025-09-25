# frozen_string_literal: true

require 'digest'

module Sequel

  # Provides efficient handling of large UNION operations.
  #
  # The unionize extension allows combining many datasets through UNION operations
  # by chunking them into manageable temporary tables or views. This is particularly
  # useful when dealing with databases that have limitations on the number of UNION
  # operations in a single query (e.g., Spark SQL, DuckDB).
  #
  # @example Load the extension
  #   DB.extension :unionize
  #
  # @example Basic usage
  #   DB.unionize([dataset1, dataset2, dataset3, dataset4])
  #
  # @example With options
  #   DB.unionize(datasets, chunk_size: 50, all: true, temp_table_prefix: 'my_union')
  module Unionize

    # Handles the chunking and union of multiple datasets.
    #
    # This class manages the process of splitting a large collection of datasets
    # into smaller chunks, creating temporary tables/views for each chunk, and
    # then recursively combining them until a single unified dataset is produced.
    class Unionizer

      # Default number of datasets to combine in each chunk
      DEFAULT_CHUNK_SIZE = 100

      # Represents a chunk of datasets to be combined via UNION.
      #
      # Each chunk handles a subset of datasets, creates a temporary table/view
      # for the combined result, and provides access to the unified dataset.
      class Chunk

        # @!attribute [r] db
        #   @return [Sequel::Database] The database connection
        # @!attribute [r] dses
        #   @return [Array<Sequel::Dataset>] The datasets in this chunk
        # @!attribute [r] opts
        #   @return [Hash] Options for the union operation
        attr_reader :db, :dses, :opts

        # Creates a new chunk instance.
        #
        # @param db [Sequel::Database] The database connection
        # @param dses [Array<Sequel::Dataset>] The datasets to combine
        # @param opts [Hash] Options for the union operation
        def initialize(db, dses, opts)
          @db = db
          @dses = dses
          @opts = opts
        end

        # Returns the unified dataset created by combining all datasets in this chunk.
        #
        # @return [Sequel::Dataset] The combined dataset
        def union
          @union ||= dses.reduce { |a, b| a.union(b, all: opts[:all], from_self: opts[:from_self]) }
        end

        # Generates a unique name for the temporary table/view.
        #
        # The name is based on a hash of the SQL query to ensure uniqueness
        # and avoid collisions when multiple unionize operations are running.
        #
        # @return [Symbol] The temporary table/view name
        def name
          @name ||= :"#{opts[:temp_table_prefix]}_#{Digest::SHA1.hexdigest(union.sql)}"
        end

        # Creates a temporary table or view for this chunk's union result.
        #
        # The method used depends on the database type:
        # - Spark: Creates a temporary view
        # - DuckDB: Creates a temporary table
        #
        # @raise [RuntimeError] If the database type is not supported
        # @return [void]
        def create
          if db.database_type == :spark
            db.create_view(name, union, temp: true)
          elsif db.database_type == :duckdb
            db.create_table(name, temp: true, as: union)
          else
            raise "Unsupported database type: #{db.database_type}"
          end
        end

      end

      # @!attribute [r] db
      #   @return [Sequel::Database] The database connection
      attr_reader :db

      # Creates a new Unionizer instance.
      #
      # @param db [Sequel::Database] The database connection
      # @param ds_set [Array<Sequel::Dataset>] The datasets to combine
      # @param opts [Hash] Options for the union operation
      # @option opts [Integer] :chunk_size (100) Number of datasets per chunk
      # @option opts [String] :temp_table_prefix ('temp_union') Prefix for temporary tables
      # @option opts [Boolean] :all (false) Use UNION ALL instead of UNION
      # @option opts [Boolean] :from_self (true) Wrap individual datasets in subqueries
      def initialize(db, ds_set, opts = {})
        @db = db
        @ds_set = ds_set
        @opts = opts
        opts[:chunk_size] ||= DEFAULT_CHUNK_SIZE
        opts[:temp_table_prefix] ||= 'temp_union'
        opts[:all] ||= false
        opts[:from_self] = opts.fetch(:from_self, true)
      end

      # Performs the unionization of datasets.
      #
      # This method recursively chunks the datasets, creates temporary tables/views
      # for each chunk, and then combines them until a single dataset remains.
      #
      # @param dses [Array<Sequel::Dataset>] The datasets to combine (defaults to @ds_set)
      # @return [Sequel::Dataset] The final combined dataset
      def unionize(dses = @ds_set)
        chunks = dses.each_slice(@opts[:chunk_size]).map do |chunk_of_dses|
          Chunk.new(db, chunk_of_dses, @opts)
        end

        return chunks.first.union if chunks.size == 1

        unionize(chunks.each(&:create).map { |chunk| db[chunk.name] })
      end

    end

    # Efficiently combines multiple datasets using UNION operations.
    #
    # This method handles large numbers of datasets by chunking them into
    # manageable groups, creating temporary tables/views for intermediate
    # results, and recursively combining them until a single dataset is produced.
    #
    # @param ds_set [Array<Sequel::Dataset>] The datasets to combine via UNION
    # @param opts [Hash] Options for the union operation
    # @option opts [Integer] :chunk_size (100) Number of datasets to combine in each chunk
    # @option opts [String] :temp_table_prefix ('temp_union') Prefix for temporary table names
    # @option opts [Boolean] :all (false) Use UNION ALL instead of UNION (keeps duplicates)
    # @option opts [Boolean] :from_self (true) Wrap individual datasets in subqueries
    #
    # @return [Sequel::Dataset] The combined dataset
    #
    # @example Basic union of datasets
    #   db.unionize([ds1, ds2, ds3, ds4])
    #
    # @example Union all with custom chunk size
    #   db.unionize(datasets, all: true, chunk_size: 50)
    #
    # @example Custom temporary table prefix
    #   db.unionize(datasets, temp_table_prefix: 'my_union_batch')
    def unionize(ds_set, opts = {})
      Unionizer.new(self, ds_set, opts).unionize
    end

  end

  Database.register_extension(:unionize, Unionize)

end
