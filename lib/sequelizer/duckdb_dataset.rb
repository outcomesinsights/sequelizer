require "pathname"

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

  # Raised when the URL's path is neither a file nor a directory, when a
  # directory URL has no dataset directory for the schema, or when that
  # directory does not hold exactly one DuckDB file.
  class MissingDatasetError < ArgumentError
    # @param path [Pathname] the path in the URL
    # @param schema [String] the dataset's schema
    # @param files [Array<Pathname>, nil] the DuckDB files in
    #   <tt><path>/<schema></tt>, or nil when +path+ is neither a file nor a
    #   directory
    def initialize(path, schema, files)
      if files.nil?
        super("#{path} is neither a DuckDB file nor a directory, so it cannot hold the dataset #{schema}")
      else
        super("#{path}/#{schema} must hold exactly one *.duckdb file to be the dataset #{schema}, " \
              "but it holds #{files.size}#{": #{files.join(", ")}" unless files.empty?}")
      end
    end
  end

  # Raised when a dataset_db call asks for other DuckDB settings or another
  # max_connections than the process's dataset database has.
  class DatasetSettingsConflictError < ArgumentError
    def initialize(held, requested)
      super("the dataset database is already open in this process with #{held.inspect}, not the " \
            "requested #{requested.inspect}. The first dataset_db call fixes them until " \
            "Sequelizer.close_dataset_dbs.")
    end
  end

  # Raised when a dataset's schema is already attached from another file.
  # The catalog name comes from the schema, so two files with one schema
  # would need one catalog.
  class DatasetSchemaConflictError < ArgumentError
    def initialize(schema, attached_file, requested_file)
      super("the schema #{schema.inspect} is already attached from #{attached_file}, so " \
            "#{requested_file} cannot be attached for it in this process")
    end
  end

  # = DuckDBDataset
  #
  # The dataset that a duckdb:// URL and a schema name identify. The URL is
  # <tt>duckdb://<path></tt>, in any case. When +path+ is a file, it is the
  # dataset file. Otherwise +path+ is a directory of datasets, and the dataset
  # file is the one <tt>*.duckdb</tt> file in <tt><path>/<schema></tt>.
  #
  # Sequelizer.dataset_db attaches it; see DuckDBDatasets.
  #
  # @example
  #   DuckDBDataset.new(url: "duckdb:///data/datasets", schema: "synpuf").dataset_file
  class DuckDBDataset
    URL_PREFIX = %r{\Aduckdb://}i

    # Whether +url+ names a directory of datasets: a duckdb:// URL whose path
    # is not an existing file.
    #
    # @param url [String] a database URL
    # @return [Boolean]
    def self.directory_url?(url)
      url.to_s.match?(URL_PREFIX) && !Pathname(url.to_s.sub(URL_PREFIX, "")).file?
    end

    # @!attribute [r] url
    #   @return [String] the duckdb:// URL of the dataset file or directory
    # @!attribute [r] schema
    #   @return [String] the dataset's schema name
    attr_reader :url, :schema

    # @param url [String] a duckdb:// URL of a dataset file or of a directory
    #   of datasets
    # @param schema [String, Symbol] the schema that holds the dataset's tables
    # @raise [UnsupportedDatasetURLError] if +url+ is not a duckdb:// URL
    def initialize(url:, schema:)
      raise UnsupportedDatasetURLError, url unless url.to_s.match?(URL_PREFIX)

      @url = url.to_s
      @schema = schema.to_s
    end

    # The DuckDB file that holds the dataset. It is found once, on the first
    # call.
    #
    # @return [Pathname] the real path of the dataset file
    # @raise [MissingDatasetError] if the URL's path is neither a file nor a
    #   directory, or if a directory URL has no single dataset file for the
    #   schema
    def dataset_file
      @dataset_file ||= find_dataset_file.realpath
    end

    private

    def find_dataset_file
      path = Pathname(url.sub(URL_PREFIX, "")).expand_path
      return path if path.file?
      raise MissingDatasetError.new(path, schema, nil) unless path.directory?

      dir = path + schema
      files = dir.directory? ? dir.glob("*.duckdb").sort : []
      raise MissingDatasetError.new(path, schema, files) unless files.one?

      files.first
    end
  end
end
