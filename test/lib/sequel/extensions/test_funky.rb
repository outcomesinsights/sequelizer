require_relative "../../../test_helper"
require "sequel"
require "sequel/extensions/funky"

class TestFunky < Minitest::Test
  def funky_db(type)
    db = Sequel.connect("mock://#{type}")
    db.extension :funky
    db
  end

  def test_mock_duckdb_connection_uses_duckdb_functions
    db = funky_db(:duckdb)

    assert_instance_of Sequel::Funky::FunkyDuckDB, db.funky
  end

  def test_mock_spark_connection_uses_spark_functions
    db = funky_db(:spark)

    assert_instance_of Sequel::Funky::FunkySpark, db.funky
  end

  def test_hash_defaults_to_md5_on_duckdb
    db = funky_db(:duckdb)
    hex = %{substr(md5(concat_ws(chr(31), coalesce(CAST("a" AS varchar(255)), chr(30)), coalesce(CAST("b" AS varchar(255)), chr(30)))), 1, 16)}
    ubigint = "CAST(('0x' || #{hex}) AS ubigint)"

    assert_equal "CAST((CASE WHEN (#{ubigint} <= 9223372036854775807) THEN #{ubigint} ELSE (#{ubigint} - 18446744073709551616) END) AS BIGINT)",
                 db.literal(db.funky.hash(:a, :b))
  end

  def test_hash_defaults_to_md5_on_spark
    db = funky_db(:spark)

    assert_equal "CAST(conv(substr(md5(concat_ws(chr(31), coalesce(CAST(`a` AS string), chr(30)), coalesce(CAST(`b` AS string), chr(30)))), 1, 16), 16, -10) AS bigint)",
                 db.literal(db.funky.hash(:a, :b))
  end

  def test_explicit_md5_strategy_matches_the_default
    %i[duckdb spark].each do |type|
      db = funky_db(type)

      assert_equal db.literal(db.funky.hash(:a, :b)), db.literal(db.funky.hash(:a, :b, strategy: :md5))
    end
  end

  def test_legacy_strategy_on_duckdb_is_hash_of_concat
    db = funky_db(:duckdb)
    hashed = %{hash(concat("a", "b"))}

    assert_equal "CAST((CASE WHEN (#{hashed} <= 9223372036854775807) THEN #{hashed} ELSE (#{hashed} - 18446744073709551616) END) AS BIGINT)",
                 db.literal(db.funky.hash(:a, :b, strategy: :legacy))
  end

  def test_legacy_strategy_on_spark_is_xxhash64
    db = funky_db(:spark)

    assert_equal "xxhash64(`a`, `b`)", db.literal(db.funky.hash(:a, :b, strategy: :legacy))
  end

  def test_unknown_strategy_raises
    %i[duckdb spark].each do |type|
      error = assert_raises(Sequel::Funky::UnknownHashStrategyError) do
        funky_db(type).funky.hash(:a, strategy: :sha256)
      end

      assert_includes error.message, ":sha256"
      assert_includes error.message, ":md5, :legacy"
    end
  end
end
