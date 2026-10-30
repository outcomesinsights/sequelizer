require "pathname"
require_relative "connection_maker"

module Sequelizer
  # Raised when a dataset URL is not a duckdb:// URL.
  class UnsupportedDatasetURLError < ArgumentError
    def initialize(url)
      super("dataset_db supports only duckdb:// URLs, not #{url.inspect}")
    end
  end

  # Raised when a dataset connection is asked to write.
  class ReadWriteDatasetError < ArgumentError
    def initialize
      super("dataset_db supports only readonly: true; read-write dataset connections are not supported yet")
    end
  end

  # Raised when a directory URL has no dataset directory for the schema, or
  # when that directory does not hold exactly one DuckDB file.
  class MissingDatasetError < ArgumentError
    def initialize(directory, schema, files)
      super("#{directory}/#{schema} must hold exactly one *.duckdb file to be the dataset #{schema}, " \
            "but it holds #{files.size}#{": #{files.join(", ")}" unless files.empty?}")
    end
  end

  # Raised when dataset_db is called again for a cached (url, schema) with
  # other DuckDB settings than the cached connection uses.
  class DatasetSettingsConflictError < ArgumentError
    def initialize(url, schema, held, requested)
      super("the dataset connection for url #{url.inspect}, schema #{schema.inspect} is already open " \
            "in this process with the DuckDB settings #{held.inspect}, not the requested settings " \
            "#{requested.inspect}. The first dataset_db call for a (url, schema) fixes its settings.")
    end
  end

  # = DuckDBDataset
  #
  # A read-only connection to one dataset in DuckDB. The connection is an
  # in-memory DuckDB database, which attaches the dataset's file read-only
  # as the catalog +dataset+. The search path is <tt>memory.main</tt>, then
  # <tt>dataset.<schema></tt>, so a table name without a schema reads the
  # dataset, and a CREATE without a catalog goes to the in-memory database.
  #
  # The URL is <tt>duckdb://<path></tt>. When +path+ is a file, it is the
  # dataset file. Otherwise +path+ is a directory of datasets, and the dataset
  # file is the one <tt>*.duckdb</tt> file in <tt><path>/<schema></tt>.
  #
  # Use Sequelizer.dataset_db, which caches one connection per (url, schema).
  #
  # @example
  #   DuckDBDataset.new(url: "duckdb:///data/datasets", schema: "synpuf").connection
  class DuckDBDataset
    URL_PREFIX = "duckdb://".freeze
    MEMORY_URL = "duckdb::memory:".freeze

    # The dataset file is attached under this fixed catalog name. A catalog
    # named like its file can equal the schema inside it (seer_x.duckdb holds
    # the schema seer_x), and DuckDB then stops with "Ambiguous reference to
    # catalog or schema".
    DATASET_CATALOG = "dataset".freeze

    # The catalog of the in-memory database. It stays first on the search
    # path: the first entry is the default database, which DuckDB cannot
    # detach, and a read-only default database makes every CREATE without a
    # catalog fail.
    MEMORY_CATALOG = "memory".freeze

    # The DuckDB settings that dataset_db accepts.
    SETTINGS = %i[memory_limit temp_directory max_temp_directory_size threads].freeze

    # Whether +url+ names a directory of datasets: a duckdb:// URL whose path
    # is not an existing file.
    #
    # @param url [String] a database URL
    # @return [Boolean]
    def self.directory_url?(url)
      url.to_s.start_with?(URL_PREFIX) && !Pathname(url.to_s.delete_prefix(URL_PREFIX)).file?
    end

    # The settings Hash in the one form that dataset_db compares: String
    # names and String values, without the settings that are nil.
    #
    # @param settings [Hash{Symbol => Object}] DuckDB settings
    # @return [Hash{String => String}]
    def self.normalize_settings(settings)
      settings.compact.to_h { |name, value| [ name.to_s, value.to_s ] }
    end

    # @!attribute [r] url
    #   @return [String] the duckdb:// URL of the dataset file or directory
    # @!attribute [r] schema
    #   @return [String] the dataset's schema name
    # @!attribute [r] settings
    #   @return [Hash{String => String}] the DuckDB settings
    attr_reader :url, :schema, :settings

    # @param url [String] a duckdb:// URL of a dataset file or of a directory
    #   of datasets
    # @param schema [String, Symbol] the schema that holds the dataset's tables
    # @param settings [Hash{String => String}] DuckDB settings, already
    #   normalized (see normalize_settings)
    # @raise [UnsupportedDatasetURLError] if +url+ is not a duckdb:// URL
    def initialize(url:, schema:, settings: {})
      raise UnsupportedDatasetURLError, url unless url.to_s.start_with?(URL_PREFIX)

      @url = url.to_s
      @schema = schema.to_s
      @settings = settings
    end

    # The DuckDB file that holds the dataset.
    #
    # @return [Pathname] the absolute path of the dataset file
    # @raise [MissingDatasetError] if a directory URL has no single dataset
    #   file for the schema
    def dataset_file
      path = Pathname(url.delete_prefix(URL_PREFIX)).expand_path
      return path unless self.class.directory_url?(url)

      dir = path + schema
      files = dir.directory? ? dir.glob("*.duckdb").sort : []
      raise MissingDatasetError.new(path, schema, files) unless files.one?

      files.first
    end

    # Opens the connection. Every new pool connection attaches the dataset
    # file read-only and sets its search path, in :after_connect. DuckDB keeps
    # an ATTACH for the whole database until its last connection closes, but
    # the search path is per connection, so both run on each connection.
    # :after_connect gets the driver's connection, which runs only SQL
    # strings, so it runs the SQL of sequel-duckdb's attach, not db.attach.
    #
    # The configuration sources (.env, environment variables and the YAML
    # files) are ignored: the URL and the settings passed here decide the
    # connection.
    #
    # @return [Sequel::Database] the connection, already tested
    # @raise [MissingDatasetError] if the dataset file cannot be found
    # @raise [Sequel::DatabaseConnectionError] if DuckDB cannot attach the file
    def connection
      file = dataset_file
      sqls = nil
      after_connect = ->(conn) { sqls.each { |sql| conn.query(sql) } }
      db = ConnectionMaker.new(url: MEMORY_URL, config: settings, after_connect: after_connect,
                               test: false, ignore_yaml: true, ignore_env: true).connection
      sqls = [
        db.attach_sql(file.to_s, as: DATASET_CATALOG, read_only: true, if_not_exists: true),
        "SET search_path = #{db.literal("#{MEMORY_CATALOG}.main,#{DATASET_CATALOG}.#{schema}")}"
      ]
      db.test_connection
      db
    end
  end
end
