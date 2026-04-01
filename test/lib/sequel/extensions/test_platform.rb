require_relative '../../../test_helper'
require 'sequel'
require 'sequel/extensions/platform'

class TestPlatform < Minitest::Test

  def setup
    # Point to the gem's config directory
    @original_config_dir = Sequel::Platform.config_dir
    Sequel::Platform.config_dir = File.expand_path('../../../../config/platforms', __dir__)
  end

  def teardown
    Sequel::Platform.config_dir = @original_config_dir
  end

  # --- Extension Registration ---

  def test_should_register_extension
    db = Sequel.mock(host: :postgres)

    assert_respond_to db, :extension

    db.extension :platform

    assert_respond_to db, :platform
  end

  def test_platform_returns_platform_instance
    db = Sequel.mock(host: :postgres)
    db.extension :platform

    assert_kind_of Sequel::Platform::Base, db.platform
  end

  # --- Platform Class Selection ---

  def test_selects_postgres_platform_for_postgres_adapter
    db = Sequel.mock(host: :postgres)
    db.extension :platform

    assert_kind_of Sequel::Platform::Postgres, db.platform
  end

  def test_selects_spark_platform_for_spark_adapter
    db = Sequel.mock(host: :spark)
    db.extension :platform

    assert_kind_of Sequel::Platform::Spark, db.platform
  end

  def test_selects_snowflake_platform_for_snowflake_adapter
    db = Sequel.mock(host: :snowflake)
    db.extension :platform

    assert_kind_of Sequel::Platform::Snowflake, db.platform
  end

  def test_selects_athena_platform_for_athena_adapter
    db = Sequel.mock(host: :athena)
    db.extension :platform

    assert_kind_of Sequel::Platform::Athena, db.platform
  end

  def test_selects_athena_platform_for_presto_adapter
    db = Sequel.mock(host: :presto)
    db.extension :platform

    assert_kind_of Sequel::Platform::Athena, db.platform
  end

  def test_selects_base_platform_for_unknown_adapter
    db = Sequel.mock(host: :sqlite)
    db.extension :platform

    assert_instance_of Sequel::Platform::Base, db.platform
  end

  def test_selects_base_platform_for_mock_duckdb_connection
    db = Sequel.connect('mock://duckdb')
    db.extension :platform

    # DuckDB doesn't have a platform class yet, so it falls back to Base
    assert_instance_of Sequel::Platform::Base, db.platform
    assert_equal :duckdb, db.database_type
  end

  # --- Config Loading ---

  def test_supports_returns_boolean_from_config
    db = Sequel.mock(host: :postgres)
    db.extension :platform

    assert db.platform.supports?(:cte)
    assert db.platform.supports?(:cte_recursive)
  end

  def test_supports_returns_false_for_unsupported_feature
    db = Sequel.mock(host: :athena)
    db.extension :platform

    refute db.platform.supports?(:temp_tables)
    refute db.platform.supports?(:cte_recursive)
  end

  def test_prefers_returns_boolean_from_config
    db = Sequel.mock(host: :postgres)
    db.extension :platform

    assert db.platform.prefers?(:cte)
  end

  def test_prefers_returns_false_when_not_preferred
    db = Sequel.mock(host: :spark)
    db.extension :platform

    refute db.platform.prefers?(:cte)
    assert db.platform.prefers?(:parquet)
  end

  def test_bracket_access_returns_config_values
    db = Sequel.mock(host: :postgres)
    db.extension :platform

    assert_equal 'search_path', db.platform[:schema_switching_method]
  end

  def test_config_stacking_overrides_base
    db = Sequel.mock(host: :athena)
    db.extension :platform

    # Athena overrides base supports_temp_tables from true to false
    refute db.platform.supports?(:temp_tables)
    # Athena overrides drop_table_needs_unquoted from false to true
    assert db.platform[:drop_table_needs_unquoted]
  end

  # --- Function Translations ---

  def test_postgres_date_diff_uses_subtraction
    db = Sequel.mock(host: :postgres)
    db.extension :platform

    expr = db.platform.date_diff(:start_date, :end_date)

    # Should produce subtraction syntax - use dataset.literal to get SQL
    sql = db.literal(expr)

    assert_includes sql, '-'
  end

  def test_spark_date_diff_uses_datediff_function
    db = Sequel.mock(host: :spark)
    db.extension :platform

    expr = db.platform.date_diff(:start_date, :end_date)

    # Should use datediff function with reversed args
    sql = db.literal(expr)

    assert_includes sql.downcase, 'datediff'
  end

  def test_snowflake_date_diff_includes_day_unit
    db = Sequel.mock(host: :snowflake)
    db.extension :platform

    expr = db.platform.date_diff(:start_date, :end_date)

    sql = db.literal(expr)

    assert_includes sql.downcase, 'datediff'
    assert_includes sql, 'day'
  end

  def test_athena_date_diff_uses_date_diff_function
    db = Sequel.mock(host: :athena)
    db.extension :platform

    expr = db.platform.date_diff(:start_date, :end_date)

    sql = db.literal(expr)

    assert_includes sql.downcase, 'date_diff'
    assert_includes sql, 'day'
  end

  def test_cast_date_returns_cast_expression
    db = Sequel.mock(host: :postgres)
    db.extension :platform

    expr = db.platform.cast_date(:some_column)

    assert_kind_of Sequel::SQL::Cast, expr
  end

  # --- Edge Cases ---

  def test_supports_unknown_feature_returns_false
    db = Sequel.mock(host: :postgres)
    db.extension :platform

    refute db.platform.supports?(:nonexistent_feature)
  end

  def test_prefers_unknown_feature_returns_false
    db = Sequel.mock(host: :postgres)
    db.extension :platform

    refute db.platform.prefers?(:nonexistent_feature)
  end

  def test_bracket_access_unknown_key_returns_nil
    db = Sequel.mock(host: :postgres)
    db.extension :platform

    assert_nil db.platform[:nonexistent_key]
  end

  def test_fetch_with_default
    db = Sequel.mock(host: :postgres)
    db.extension :platform

    # Known key
    assert_equal 'search_path', db.platform.fetch(:schema_switching_method, 'default')
    # Unknown key
    assert_equal 'default', db.platform.fetch(:unknown_key, 'default')
  end

end

class TestPlatformExtended < Minitest::Test

  def setup
    @original_config_dir = Sequel::Platform.config_dir
    Sequel::Platform.config_dir = File.expand_path('../../../../config/platforms', __dir__)
  end

  def teardown
    Sequel::Platform.config_dir = @original_config_dir
  end

  # --- Additional Function Translations ---

  def test_base_str_to_date_returns_to_date_function
    db = Sequel.mock(host: :sqlite)
    db.extension :platform

    expr = db.platform.str_to_date('2024-01-15', '%Y-%m-%d')
    sql = db.literal(expr)

    assert_includes sql.downcase, 'to_date'
  end

  def test_spark_str_to_date_casts_to_string_first
    db = Sequel.mock(host: :spark)
    db.extension :platform

    expr = db.platform.str_to_date(:date_col, '%Y-%m-%d')
    sql = db.literal(expr)

    assert_includes sql.downcase, 'to_date'
    assert_includes sql.downcase, 'cast'
  end

  def test_postgres_days_between_uses_subtraction
    db = Sequel.mock(host: :postgres)
    db.extension :platform

    expr = db.platform.days_between(:start_date, :end_date)
    sql = db.literal(expr)

    assert_includes sql, '-'
  end

  def test_snowflake_days_between_uses_datediff
    db = Sequel.mock(host: :snowflake)
    db.extension :platform

    expr = db.platform.days_between(:start_date, :end_date)
    sql = db.literal(expr)

    assert_includes sql.downcase, 'datediff'
    assert_includes sql, 'day'
  end

  def test_athena_days_between_uses_date_diff
    db = Sequel.mock(host: :athena)
    db.extension :platform

    expr = db.platform.days_between(:start_date, :end_date)
    sql = db.literal(expr)

    assert_includes sql.downcase, 'date_diff'
    assert_includes sql, 'day'
  end

  # --- Adapter Aliases ---

  def test_selects_athena_platform_for_trino_adapter
    db = Sequel.mock(host: :trino)
    db.extension :platform

    assert_kind_of Sequel::Platform::Athena, db.platform
  end

  def test_selects_postgres_platform_for_postgresql_adapter
    db = Sequel.mock(host: :postgresql)
    db.extension :platform

    assert_kind_of Sequel::Platform::Postgres, db.platform
  end

  # --- Extra Config Paths ---

  def test_accepts_extra_platform_configs
    extra = File.expand_path('../../../../config/platforms/rdbms/athena.csv', __dir__)
    db = Sequel.mock(host: :postgres, platform_configs: [extra])
    db.extension :platform

    # Athena config overrides drop_table_needs_unquoted to true
    assert db.platform[:drop_table_needs_unquoted]
  end

  # --- Effective Adapter ---

  def test_effective_adapter_uses_database_type_for_real_connections
    db = Sequel.connect('mock://duckdb')
    adapter = Sequel::Platform.effective_adapter(db)

    assert_equal :duckdb, adapter
  end

  def test_effective_adapter_falls_back_to_host_for_mock
    db = Sequel.mock(host: :snowflake)
    adapter = Sequel::Platform.effective_adapter(db)

    assert_equal :snowflake, adapter
  end

  # --- Custom Adapter Registration ---

  def test_register_custom_platform_class
    custom_class = Class.new(Sequel::Platform::Base)
    Sequel::Platform.register(:mydb, custom_class)

    db = Sequel.mock(host: :mydb)
    db.extension :platform

    assert_kind_of custom_class, db.platform
  ensure
    Sequel::Platform.reset_registries!
  end

  def test_register_with_config_name
    custom_class = Class.new(Sequel::Platform::Base)
    Sequel::Platform.register(:mydb, custom_class, 'postgres')

    assert_equal 'postgres', Sequel::Platform.adapter_config_names[:mydb]
  ensure
    Sequel::Platform.reset_registries!
  end

  def test_register_multiple_aliases
    custom_class = Class.new(Sequel::Platform::Base)
    Sequel::Platform.register(%i[alias_a alias_b], custom_class)

    db_a = Sequel.mock(host: :alias_a)
    db_a.extension :platform

    db_b = Sequel.mock(host: :alias_b)
    db_b.extension :platform

    assert_kind_of custom_class, db_a.platform
    assert_kind_of custom_class, db_b.platform
  ensure
    Sequel::Platform.reset_registries!
  end

  def test_register_overrides_default
    custom_class = Class.new(Sequel::Platform::Postgres)
    Sequel::Platform.register(:postgres, custom_class)

    db = Sequel.mock(host: :postgres)
    db.extension :platform

    assert_kind_of custom_class, db.platform
  ensure
    Sequel::Platform.reset_registries!
  end

  def test_reset_registries_restores_defaults
    custom_class = Class.new(Sequel::Platform::Base)
    Sequel::Platform.register(:mydb, custom_class)

    Sequel::Platform.reset_registries!

    db = Sequel.mock(host: :mydb)
    db.extension :platform

    # Should fall back to Base since registry was reset
    assert_instance_of Sequel::Platform::Base, db.platform
  end

  def test_unregistered_adapter_falls_back_to_base
    db = Sequel.mock(host: :unknown_db)
    db.extension :platform

    assert_instance_of Sequel::Platform::Base, db.platform
  end

end
