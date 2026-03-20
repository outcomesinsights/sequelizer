# frozen_string_literal: true

#
# The platform extension provides a unified interface for platform-specific
# database behavior. It uses KVCSV configuration files to define capabilities
# and preferences, with Ruby classes only for function translations.
#
#   DB.extension :platform
#   DB.platform.supports?(:cte)           # => true (from config)
#   DB.platform.prefers?(:cte)            # => true (from config)
#   DB.platform[:interim_schema]          # => nil (from config)
#   DB.platform.date_diff(from, to)       # => Sequel expression (from code)
#
# Configuration is loaded from CSV files in config/platforms/:
#   - base.csv: conservative defaults
#   - rdbms/<adapter>.csv: RDBMS-specific overrides
#   - Additional configs can be stacked via platform_configs option
#
# Related module: Sequel::Platform

require 'kvcsv'

module Sequel

  # The Platform module provides database platform abstraction through
  # configuration-driven capabilities and code-driven function translations.
  module Platform

    # Base platform class with KVCSV config loading and default implementations.
    # Subclasses override function translation methods for platform-specific SQL.
    class Base

      attr_reader :db, :config

      # Initialize platform with database connection and config paths.
      #
      # @param db [Sequel::Database] The database connection
      # @param config_paths [Array<String>] Paths to CSV config files (stacked in order)
      def initialize(db, *config_paths)
        @db = db
        @config = config_paths.empty? ? {} : KVCSV::Settings.new(*config_paths)
      end

      # Check if the platform supports a feature.
      #
      # @param feature [Symbol] Feature name (e.g., :cte, :temp_tables)
      # @return [Boolean] true if supported
      #
      # @example
      #   platform.supports?(:cte)           # checks supports_cte in config
      #   platform.supports?(:temp_tables)   # checks supports_temp_tables in config
      def supports?(feature)
        config[:"supports_#{feature}"] || false
      end

      # Check if the platform prefers a feature (may support but not prefer).
      #
      # @param feature [Symbol] Feature name (e.g., :cte, :parquet)
      # @return [Boolean] true if preferred
      #
      # @example
      #   platform.prefers?(:cte)      # Spark supports CTEs but doesn't prefer them
      #   platform.prefers?(:parquet)  # Spark prefers parquet format
      def prefers?(feature)
        config[:"prefers_#{feature}"] || false
      end

      # Access arbitrary config values.
      #
      # @param key [Symbol] Config key
      # @return [Object] Config value or nil
      #
      # @example
      #   platform[:interim_schema]           # => "scratch"
      #   platform[:schema_switching_method]  # => "use"
      def [](key)
        config[key]
      end

      # Fetch config value with default.
      #
      # @param key [Symbol] Config key
      # @param default [Object] Default value if key not found
      # @return [Object] Config value or default
      def fetch(key, default = nil)
        config.respond_to?(:fetch) ? config.fetch(key, default) : (config[key] || default)
      end

      # ---- Function translations (override in subclasses) ----

      # Calculate date difference between two dates.
      #
      # @param from [Symbol, Sequel::SQL::Expression] Start date
      # @param to [Symbol, Sequel::SQL::Expression] End date
      # @return [Sequel::SQL::Expression] Date difference expression
      def date_diff(from, to)
        Sequel.function(:datediff, from, to)
      end

      # Cast expression to date type.
      #
      # @param expr [Object] Expression to cast
      # @return [Sequel::SQL::Cast] Cast expression
      def cast_date(expr)
        Sequel.cast(expr, Date)
      end

      # Parse string to date with format.
      #
      # @param value [Object] String value to parse
      # @param format [String] Date format string
      # @return [Sequel::SQL::Expression] Parsed date expression
      def str_to_date(value, format)
        Sequel.function(:to_date, value, format)
      end

      # Calculate days between two dates.
      #
      # @param from [Symbol, Sequel::SQL::Expression] Start date
      # @param to [Symbol, Sequel::SQL::Expression] End date
      # @return [Sequel::SQL::Expression] Days between expression
      def days_between(from, to)
        date_diff(from, to)
      end

    end

    # PostgreSQL platform with Postgres-specific function translations.
    class Postgres < Base

      def date_diff(from, to)
        # Postgres uses date subtraction
        Sequel.lit('(? - ?)', to, from)
      end

      def days_between(from, to)
        # Postgres date subtraction returns integer days
        Sequel.lit('(? - ?)', to, from)
      end

    end

    # Spark platform with Spark SQL-specific function translations.
    class Spark < Base

      def date_diff(from, to)
        # Spark datediff has reversed argument order (end, start)
        Sequel.function(:datediff, to, from)
      end

      def str_to_date(value, format)
        Sequel.function(:to_date, Sequel.cast_string(value), format)
      end

    end

    # Snowflake platform with Snowflake-specific function translations.
    class Snowflake < Base

      def date_diff(from, to)
        # Snowflake requires unit parameter
        Sequel.function(:datediff, 'day', from, to)
      end

      def days_between(from, to)
        Sequel.function(:datediff, 'day', from, to)
      end

    end

    # Athena platform (Presto/Trino based) with Athena-specific function translations.
    class Athena < Base

      def date_diff(from, to)
        # Athena/Presto uses date_diff with unit
        Sequel.function(:date_diff, 'day', from, to)
      end

      def days_between(from, to)
        Sequel.function(:date_diff, 'day', from, to)
      end

    end

    # Map adapter schemes to platform classes
    PLATFORM_CLASSES = {
      postgres: Postgres,
      postgresql: Postgres,
      spark: Spark,
      athena: Athena,
      presto: Athena,
      trino: Athena,
      snowflake: Snowflake,
    }.freeze

    # Map adapter schemes to config file names
    ADAPTER_CONFIG_NAMES = {
      postgres: 'postgres',
      postgresql: 'postgres',
      spark: 'spark',
      athena: 'athena',
      presto: 'athena',
      trino: 'athena',
      snowflake: 'snowflake',
    }.freeze

    class << self

      # Find the config directory, searching gem paths
      def config_dir
        @config_dir ||= find_config_dir
      end

      # Allow overriding config dir for testing
      attr_writer :config_dir

      private

      def find_config_dir
        # Check relative to this file (gem's config)
        gem_config = File.expand_path('../../../config/platforms', __dir__)
        return gem_config if File.directory?(gem_config)

        # Fallback to working directory
        local_config = File.join(Dir.pwd, 'config/platforms')
        return local_config if File.directory?(local_config)

        nil
      end

    end

    # Build config paths for the given adapter
    #
    # @param adapter_scheme [Symbol] Database adapter scheme
    # @param extra_configs [Array<String>] Additional config paths to stack
    # @return [Array<String>] Ordered config paths
    def self.config_paths_for(adapter_scheme, extra_configs = [])
      paths = []

      if config_dir
        base_config = File.join(config_dir, 'base.csv')
        paths << base_config if File.exist?(base_config)

        adapter_name = ADAPTER_CONFIG_NAMES[adapter_scheme]
        if adapter_name
          rdbms_config = File.join(config_dir, 'rdbms', "#{adapter_name}.csv")
          paths << rdbms_config if File.exist?(rdbms_config)
        end
      end

      paths.concat(extra_configs.select { |p| File.exist?(p) })
      paths
    end

    # Build platform instance for database
    #
    # @param db [Sequel::Database] Database connection
    # @param extra_configs [Array<String>] Additional config paths
    # @return [Platform::Base] Platform instance
    def self.build_platform(db, extra_configs = [])
      adapter = effective_adapter(db)
      platform_class = PLATFORM_CLASSES.fetch(adapter, Base)
      config_paths = config_paths_for(adapter, extra_configs)
      platform_class.new(db, *config_paths)
    end

    # Returns the effective database type for platform selection.
    #
    # For real connections, database_type is authoritative.  For mock
    # connections whose shared adapter isn't installed (e.g. snowflake,
    # athena), database_type returns :mock; fall back to opts[:host].
    #
    # @param db [Sequel::Database] Database connection
    # @return [Symbol] Effective database type
    def self.effective_adapter(db)
      db_type = db.database_type
      return db_type unless db_type == :mock

      db.opts[:host]&.to_sym
    end

    # Extension hook - called when extension is loaded
    def self.extended(db)
      extra_configs = db.opts[:platform_configs] || []
      db.instance_variable_set(:@platform, build_platform(db, extra_configs))
    end

    # Access the platform instance
    #
    # @return [Platform::Base] Platform instance for this database
    def platform
      @platform
    end

  end

  Database.register_extension(:platform, Platform)

end
