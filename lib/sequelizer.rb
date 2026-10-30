require_relative "sequelizer/version"
require_relative "sequelizer/connection_maker"
require_relative "sequelizer/duckdb_dataset"
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

  @dataset_dbs = {}
  @dataset_dbs_mutex = Mutex.new

  # Returns a read-only connection to one DuckDB dataset, cached per process
  # by (url, schema). Every thread that asks for the same (url, schema) gets
  # the same Sequel::Database.
  #
  # The connection is an in-memory DuckDB database that attaches the dataset
  # file read-only, so a write to a dataset table fails. Its search path puts
  # the dataset's schema after the in-memory database, so a table name without
  # a schema reads the dataset (<tt>db[:patients]</tt>), and a CREATE without
  # a catalog goes to the in-memory database. See DuckDBDataset.
  #
  # The DuckDB settings apply to the in-memory database when it opens. A
  # setting that is nil keeps DuckDB's default. DuckDB's default memory_limit
  # is 80% of the memory that the container may use, for each DuckDB database
  # in the process, so pass memory_limit where more than one runs.
  #
  # The .env file, environment variables and YAML files are not read.
  #
  # @param url [String] <tt>duckdb://<directory></tt>, a directory that holds
  #   one directory for each dataset, <tt><directory>/<schema>/</tt>, with
  #   exactly one <tt>*.duckdb</tt> file in it; or <tt>duckdb://<file></tt>,
  #   an existing DuckDB file, which is attached directly
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
  # @return [Sequel::Database] the cached read-only connection
  # @raise [ReadWriteDatasetError] if +readonly+ is false
  # @raise [UnsupportedDatasetURLError] if +url+ is not a duckdb:// URL
  # @raise [MissingDatasetError] if a directory URL has no single DuckDB file
  #   for +schema+
  # @raise [DatasetSettingsConflictError] if (url, schema) is cached with other
  #   DuckDB settings
  #
  # @example
  #   db = Sequelizer.dataset_db(url: "duckdb:///data/datasets", schema: "synpuf",
  #                              memory_limit: "51GB", temp_directory: "/scratch/duckdb",
  #                              max_temp_directory_size: "500GB")
  #   db[:patients].count
  def self.dataset_db(url:, schema:, readonly: true, memory_limit: nil, temp_directory: nil,
                      max_temp_directory_size: nil, threads: nil)
    raise ReadWriteDatasetError unless readonly

    settings = DuckDBDataset.normalize_settings(memory_limit:, temp_directory:, max_temp_directory_size:, threads:)
    key = [ url.to_s, schema.to_s ]

    @dataset_dbs_mutex.synchronize do
      cached = @dataset_dbs[key] ||= { db: DuckDBDataset.new(url:, schema:, settings:).connection, settings: }
      raise DatasetSettingsConflictError.new(*key, cached[:settings], settings) unless cached[:settings] == settings

      cached[:db]
    end
  end

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
