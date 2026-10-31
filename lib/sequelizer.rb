require_relative "sequelizer/version"
require_relative "sequelizer/connection_maker"
require_relative "sequelizer/duckdb_datasets"
require_relative "sequel/extensions/db_opts"
require_relative "sequel/extensions/settable"

# = Sequelizer
#
# Sequelizer is a Ruby gem that simplifies database connections using Sequel.
# It allows users to configure database connections via config/sequelizer.yml
# or .env files, providing an easy-to-use interface for establishing database
# connections without hardcoding sensitive information.
#
# == Usage
#
# Include this module in any class where you'd like to quickly establish
# a Sequel connection to a database:
#
#   class MyClass
#     include Sequelizer
#
#     def some_method
#       db[:users].all  # Uses cached connection
#     end
#   end
#
# == Configuration Sources
#
# Configuration is loaded from multiple sources in order of precedence:
# 1. Passed options
# 2. .env file
# 3. Environment variables
# 4. config/sequelizer.yml
# 5. ~/.config/sequelizer/database.yml
#
# == Examples
#
#   # Use cached connection
#   db[:users].all
#
#   # Create new connection with custom options
#   new_db(adapter: 'postgres', host: 'localhost')
#
module Sequelizer
  # Returns the default options hash for database connections.
  #
  # @return [Hash] the default connection options
  def self.options
    Options.new.to_hash
  end

  @duckdb_datasets = DuckDBDatasets.new

  # Attaches one DuckDB dataset read-only and returns the process's dataset
  # database: one in-memory DuckDB database that every dataset in the process
  # shares. The dataset file is attached at the first call for it, under the
  # catalog <tt>dataset_<schema></tt>, and stays attached until
  # close_dataset_dbs. Every call returns the same Sequel::Database.
  #
  # Name a dataset's tables with the catalog, the schema and the table:
  # <tt>Sequel[Sequelizer.dataset_catalog(:synpuf)][:synpuf][:patients]</tt>.
  # A name with only a schema and a table, or with only a table, reads a
  # dataset only inside with_dataset. Outside it, DuckDB raises a Catalog
  # Error. A write to a dataset table fails.
  #
  # The DuckDB settings and +max_connections+ apply once, to the one
  # database, so memory_limit and max_temp_directory_size are limits for all
  # the datasets together. The first call fixes them until close_dataset_dbs.
  # A setting that is nil keeps DuckDB's default. DuckDB's default
  # memory_limit is 80% of the memory that the container may use, for each
  # DuckDB database. Two processes must not share one temp_directory: DuckDB
  # gives the spill files the same names in every database.
  #
  # Each schema can come from one file in a process, because the catalog name
  # comes from the schema. The dataset file is the real path of the file that +url+
  # resolves to, so two URLs for one file are one dataset.
  #
  # A file that is replaced on disk after it is attached is not read, even
  # after +disconnect+. Call close_dataset_dbs, or restart the process, to
  # read the new file.
  #
  # The .env file, environment variables and YAML files are not read.
  #
  # @param url [String] <tt>duckdb://<directory></tt>, a directory that holds
  #   one directory for each dataset, <tt><directory>/<schema>/</tt>, with
  #   exactly one <tt>*.duckdb</tt> file in it; or <tt>duckdb://<file></tt>,
  #   an existing DuckDB file, which is attached directly. The scheme can be
  #   in any case.
  # @param schema [String, Symbol] the schema in the DuckDB file that holds the
  #   dataset's tables
  # @param readonly [Boolean] must be true; read-write connections are not
  #   supported yet
  # @param memory_limit [String, nil] DuckDB's memory_limit, for example "51GB"
  # @param temp_directory [String, nil] DuckDB's temp_directory, where it
  #   spills data that does not fit in memory
  # @param max_temp_directory_size [String, nil] DuckDB's
  #   max_temp_directory_size, for example "500GB"
  # @param threads [Integer, String, nil] DuckDB's threads
  # @param max_connections [Integer, nil] the size of the database's
  #   connection pool, for example the number of threads that use it; nil
  #   keeps Sequel's default of 4
  # @return [Sequel::Database] the process's dataset database
  # @raise [ReadWriteDatasetError] if +readonly+ is false
  # @raise [UnsupportedDatasetURLError] if +url+ is not a duckdb:// URL
  # @raise [MissingDatasetError] if the URL's path is neither a file nor a
  #   directory, or if a directory URL has no single DuckDB file for +schema+
  # @raise [DatasetSettingsConflictError] if the database is open with other
  #   DuckDB settings or another max_connections
  # @raise [DatasetSchemaConflictError] if +schema+ is attached from another
  #   file
  #
  # @example
  #   db = Sequelizer.dataset_db(url: "duckdb:///data/datasets", schema: "synpuf",
  #                              memory_limit: "51GB", temp_directory: "/scratch/duckdb",
  #                              max_temp_directory_size: "500GB", max_connections: 5)
  #   db[Sequel[Sequelizer.dataset_catalog(:synpuf)][:synpuf][:patients]].count
  def self.dataset_db(url:, schema:, **options)
    @duckdb_datasets.attach(url:, schema:, options: dataset_options(**options)).first
  end

  # Attaches the dataset like dataset_db, and runs the block on one
  # connection whose search path is <tt>memory.main</tt>, then the dataset's
  # schema. A table name without a schema reads the dataset in the block,
  # as ConceptQL's SQL needs (<tt>db[:patients]</tt>). The search path is
  # restored when the block ends, so a query outside the block, or a lazy
  # dataset that runs after it, finds no dataset table and fails.
  #
  # A CREATE without a catalog goes to the in-memory database, which comes
  # first on the search path, so a created table hides the dataset table of
  # the same name in the block. The in-memory database is shared by every
  # dataset and thread in the process.
  #
  # +search_path_prefix+ puts other DuckDB search path entries first, for
  # example a read-write catalog that the caller attached to the dataset
  # database. A CREATE without a catalog then goes to the first entry. An
  # entry is a catalog (DuckDB reads +working+ as <tt>working.main</tt>) or
  # <tt>catalog.schema</tt>. DuckDB raises a Catalog Error, before the block
  # runs, for an entry that is not attached.
  #
  # @param (see dataset_db)
  # @param search_path_prefix [String, Symbol, Array<String, Symbol>] the
  #   search path entries that come before <tt>memory.main</tt> and the
  #   dataset, in order
  # @yieldparam db [Sequel::Database] the process's dataset database
  # @return [Object] the block's value
  # @raise [SearchPathEntryError] if a search_path_prefix entry is empty or
  #   holds a comma
  #
  # @example
  #   Sequelizer.with_dataset(url: "duckdb:///data/datasets", schema: "synpuf") do |db|
  #     db[:patients].count
  #   end
  #
  # @example A read-write catalog first
  #   db = Sequelizer.dataset_db(url: "duckdb:///data/datasets", schema: "synpuf")
  #   db.attach("/scratch/working.duckdb", as: "working")
  #   Sequelizer.with_dataset(url: "duckdb:///data/datasets", schema: "synpuf",
  #                           search_path_prefix: "working.main") do |d|
  #     d.create_table(:results) { Integer :person_id } # working.main.results
  #   end
  def self.with_dataset(url:, schema:, search_path_prefix: [], **options, &)
    @duckdb_datasets.with_dataset(url:, schema:, options: dataset_options(**options),
                                  search_path_prefix: Array(search_path_prefix), &)
  end

  # The catalog that the dataset with +schema+ is attached as, for a table
  # name outside with_dataset:
  # <tt>Sequel[Sequelizer.dataset_catalog(:synpuf)][:synpuf][:patients]</tt>.
  #
  # @param schema [String, Symbol] the dataset's schema
  # @return [Symbol] <tt>:dataset_<schema></tt>
  def self.dataset_catalog(schema) = DuckDBDatasets.catalog_for(schema)

  # Detaches every dataset file and closes the process's dataset database,
  # so the next dataset_db call opens a new database with the files that are
  # on disk then.
  #
  # Call it when no thread uses the dataset database, for example between
  # tests, at shutdown, or after a dataset file is replaced. Do not use a
  # Sequel::Database that dataset_db returned before the call.
  #
  # @return [void]
  def self.close_dataset_dbs
    @duckdb_datasets.close
  end

  def self.dataset_options(readonly: true, memory_limit: nil, temp_directory: nil, max_temp_directory_size: nil,
                           threads: nil, max_connections: nil)
    raise ReadWriteDatasetError unless readonly

    settings = { memory_limit:, temp_directory:, max_temp_directory_size:, threads: }
               .compact.to_h { |name, value| [ name.to_s, value.to_s ] }
    { settings:, max_connections: }
  end
  private_class_method :dataset_options

  # Instantiates and memoizes a database connection. The +db+ method instantiates
  # the connection on the first call and then memoizes itself so only a single
  # connection is used on repeated calls.
  #
  # @param options [Hash, String] an optional set of database connection options,
  #   or a database URL string, which means { url: string }.
  #   If no options are provided, options are read from config/sequelizer.yml
  #   or from .env or from environment variables.
  # @return [Sequel::Database] the memoized database connection
  #
  # @example
  #   db[:users].all  # Uses cached connection
  #   db(adapter: 'postgres')[:products].count
  def db(options = {})
    @_sequelizer_db ||= new_db(options)
  end

  # Instantiates and returns a new database connection on each call.
  #
  # @param options [Hash, String] an optional set of database connection options,
  #   or a database URL string, which means { url: string }.
  #   If no options are provided, options are read from config/sequelizer.yml
  #   or from .env or from environment variables.
  # @return [Sequel::Database] a new database connection
  #
  # @example
  #   conn1 = new_db
  #   conn2 = new_db  # Different connection instance
  #   new_db(force_new: true)  # Bypasses cache entirely
  def new_db(options = {})
    options = { url: options } if options.is_a?(String)
    cached = find_cached(options)
    return cached if cached && !options[:force_new]

    @_sequelizer_cache[options] = ConnectionMaker.new(options).connection
  end

  # Finds a cached connection for the given options.
  #
  # @param options [Hash, String] the connection options to look up, or a
  #   database URL string, which means { url: string }
  # @return [Sequel::Database, nil] the cached connection or nil if not found
  def find_cached(options)
    options = { url: options } if options.is_a?(String)
    @_sequelizer_cache ||= {}
    @_sequelizer_cache[options]
  end
end
