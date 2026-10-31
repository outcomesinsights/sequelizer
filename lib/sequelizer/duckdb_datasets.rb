require_relative "connection_maker"
require_relative "duckdb_dataset"

module Sequelizer
  # = DuckDBDatasets
  #
  # The read-only DuckDB datasets of one process. The process has one
  # in-memory DuckDB database, so memory_limit, temp_directory,
  # max_temp_directory_size and threads apply once, and the datasets use one
  # set of spill files. Each dataset file is attached READ_ONLY once, under
  # the catalog <tt>dataset_<schema></tt>.
  #
  # A table named with its catalog, schema and table
  # (<tt>Sequel[:dataset_synpuf][:synpuf][:patients]</tt>) reads the dataset
  # on any connection. A name with only a schema and a table, or with only a
  # table, reads a dataset only inside with_dataset, which sets the
  # connection's search path for the block.
  #
  # The attached files stay attached until close, so a dataset file that is
  # replaced on disk is not read until then.
  #
  # Use Sequelizer.dataset_db, Sequelizer.with_dataset and
  # Sequelizer.close_dataset_dbs.
  class DuckDBDatasets
    MEMORY_URL = "duckdb::memory:".freeze

    # The schema of the in-memory database. It comes first on a dataset's
    # search path: the first entry is where a CREATE without a catalog goes,
    # and a read-only dataset there makes every such CREATE fail.
    MEMORY_SCHEMA = "memory.main".freeze

    # The catalog that the dataset with +schema+ is attached as.
    #
    # @param schema [String, Symbol] the dataset's schema
    # @return [Symbol] <tt>:dataset_<schema></tt>
    def self.catalog_for(schema) = :"dataset_#{schema}"

    def initialize
      @mutex = Mutex.new
      reset
    end

    # Attaches the dataset, if it is not attached yet.
    #
    # @param url [String] a duckdb:// URL (see DuckDBDataset)
    # @param schema [String, Symbol] the dataset's schema
    # @param options [Hash] <tt>{ settings: Hash{String => String},
    #   max_connections: Integer or nil }</tt>
    # @return [Array(Sequel::Database, String)] the process's dataset database
    #   and the dataset's catalog
    # @raise [DatasetSettingsConflictError] if +options+ differ from the open
    #   database's
    # @raise [DatasetSchemaConflictError] if the schema is attached from
    #   another file
    def attach(url:, schema:, options:)
      dataset = DuckDBDataset.new(url:, schema:)
      file = dataset.dataset_file.to_s

      @mutex.synchronize do
        forget_parent_process
        raise DatasetSettingsConflictError.new(@options, options) if @db && @options != options

        begin
          @db ||= connect(options)
          @options = options
          [ @db, attach_file(file, dataset.schema) ]
        rescue StandardError
          close_db if @schemas.empty?
          raise
        end
      end
    end

    # Attaches the dataset, holds one connection for the block, and sets the
    # connection's search path to the +search_path_prefix+ entries, then
    # <tt>memory.main,<catalog>.<schema></tt>, so a table name without a
    # schema reads the dataset. At the end of the block, the search path is
    # what it was before.
    #
    # @param search_path_prefix [Array<String, Symbol>] DuckDB search path
    #   entries to put first
    # @yieldparam db [Sequel::Database] the process's dataset database
    # @return [Object] the block's value
    # @raise [SearchPathEntryError] if an entry is empty or holds a comma
    def with_dataset(url:, schema:, options:, search_path_prefix: [])
      prefix = search_path_prefix.map(&:to_s)
      bad = prefix.select { |entry| entry.empty? || entry.include?(",") }
      raise SearchPathEntryError, bad unless bad.empty?

      db, catalog = attach(url:, schema:, options:)
      path = [ *prefix, MEMORY_SCHEMA, "#{catalog}.#{schema}" ].join(",")

      db.synchronize do
        previous = db.get(Sequel.function(:current_setting, "search_path"))
        db.run("SET search_path = #{db.literal(path)}")
        begin
          yield db
        ensure
          db.run("SET search_path = #{db.literal(previous)}")
        end
      end
    end

    # Detaches every dataset file and disconnects the database. The next
    # attach opens a new database.
    #
    # @return [void]
    def close
      @mutex.synchronize do
        forget_parent_process
        close_db
      end
    end

    private

    def reset
      @pid = Process.pid
      @db = nil
      @options = nil
      @catalogs = {}
      @schemas = {}
    end

    # A forked child inherits the parent's database, but its DuckDB instance
    # belongs to the parent. The child opens its own.
    def forget_parent_process
      reset unless @pid == Process.pid
    end

    # The catalog of +file+, which this attaches the first time. The catalog
    # name has a prefix, because a catalog named like a schema in its file
    # makes DuckDB stop with "Ambiguous reference to catalog or schema".
    def attach_file(file, schema)
      if (held = @schemas[schema])
        raise DatasetSchemaConflictError.new(schema, held[:file], file) unless held[:file] == file

        return held[:catalog]
      end

      catalog = @catalogs[file]
      unless catalog
        catalog = self.class.catalog_for(schema).to_s
        @db.attach(file, as: catalog, read_only: true)
        @catalogs[file] = catalog
      end
      @schemas[schema] = { file:, catalog: }
      catalog
    end

    def close_db
      if @db
        @catalogs.each_value { |catalog| @db.detach(catalog, if_exists: true) }
        @db.disconnect
      end
      reset
    end

    # The in-memory database. The configuration sources (.env, environment
    # variables and the YAML files) are ignored, and Sequel::DATABASES does
    # not hold it, so a closed database can be garbage collected.
    def connect(options)
      opts = { url: MEMORY_URL, config: options[:settings], test: false, keep_reference: false,
               ignore_yaml: true, ignore_env: true }
      opts[:max_connections] = options[:max_connections] if options[:max_connections]
      db = ConnectionMaker.new(opts).connection
      db.test_connection
      db
    end
  end
end
