require_relative "../../../test_helper"
require "sequel"
require "sequel/extensions/settable"

class TestSettable < Minitest::Test
  def test_should_register_extension
    db = Sequel.mock(host: :sqlite)

    assert_respond_to db, :extension
    db.extension :settable

    assert_respond_to db, :set
  end

  def test_set_with_single_option
    db = Sequel.mock(host: :sqlite)
    db.extension :settable
    db.set(search_path: "public")

    assert_equal([ "SET search_path=public" ], db.sqls)
  end

  def test_set_with_multiple_options
    db = Sequel.mock(host: :sqlite)
    db.extension :settable
    db.set(search_path: "public", timezone: "UTC")

    expected_sqls = [ "SET search_path=public", "SET timezone=UTC" ]

    assert_equal expected_sqls, db.sqls
  end

  def test_set_with_empty_hash
    db = Sequel.mock(host: :sqlite)
    db.extension :settable
    db.set({})

    assert_empty(db.sqls)
  end

  def test_set_with_no_arguments
    db = Sequel.mock(host: :sqlite)
    db.extension :settable
    db.set

    assert_empty(db.sqls)
  end

  def test_set_with_string_values
    db = Sequel.mock(host: :sqlite)
    db.extension :settable
    db.set(work_mem: "256MB", statement_timeout: "30s")

    expected_sqls = [ "SET work_mem=256MB", "SET statement_timeout=30s" ]

    assert_equal expected_sqls, db.sqls
  end

  def test_set_with_numeric_values
    db = Sequel.mock(host: :sqlite)
    db.extension :settable
    db.set(port: 5432, max_connections: 100)

    expected_sqls = [ "SET port=5432", "SET max_connections=100" ]

    assert_equal expected_sqls, db.sqls
  end

  def test_set_with_boolean_values
    db = Sequel.mock(host: :sqlite)
    db.extension :settable
    db.set(autocommit: true, log_statement: false)

    expected_sqls = [ "SET autocommit=true", "SET log_statement=false" ]

    assert_equal expected_sqls, db.sqls
  end

  def test_set_with_nil_values
    db = Sequel.mock(host: :sqlite)
    db.extension :settable
    db.set(timezone: nil, search_path: nil)

    expected_sqls = [ "SET timezone=", "SET search_path=" ]

    assert_equal expected_sqls, db.sqls
  end

  def test_set_sql_is_public_and_does_not_execute
    db = Sequel.mock(host: :sqlite)
    db.extension :settable

    assert_equal([ "SET search_path=public" ], db.set_sql(search_path: "public"))
    assert_empty(db.sqls)
  end

  def test_set_quotes_expression_string_on_duckdb
    db = duckdb_mock
    db.set(memory_limit: Sequel.expr("1GB"))

    assert_equal([ "SET memory_limit='1GB'" ], db.sqls)
  end

  def test_set_escapes_quote_in_expression_string_on_duckdb
    db = duckdb_mock
    db.set(note: Sequel.expr("it's"))

    assert_equal([ "SET note='it''s'" ], db.sqls)
  end

  def test_set_literalizes_expression_integer_on_duckdb
    db = duckdb_mock
    db.set(threads: Sequel.expr(4))

    assert_equal([ "SET threads=4" ], db.sqls)
  end

  def test_set_literalizes_expression_boolean_on_duckdb
    db = duckdb_mock
    db.set(preserve_insertion_order: Sequel.expr(true))

    assert_equal([ "SET preserve_insertion_order=TRUE" ], db.sqls)
  end

  def test_set_keeps_plain_string_raw_on_duckdb
    db = duckdb_mock
    db.set(threads: "4")

    assert_equal([ "SET threads=4" ], db.sqls)
  end

  def test_set_quotes_only_wrapped_values_in_mixed_hash
    db = duckdb_mock
    db.set(memory_limit: Sequel.expr("1GB"), threads: "4")

    assert_equal([ "SET memory_limit='1GB'", "SET threads=4" ], db.sqls)
  end

  def test_multiple_set_calls
    db = Sequel.mock(host: :sqlite)
    db.extension :settable

    db.set(timezone: "UTC")
    db.set(search_path: "public")

    expected_sqls = [ "SET timezone=UTC", "SET search_path=public" ]

    assert_equal expected_sqls, db.sqls
  end

  private

  def duckdb_mock
    db = Sequel.mock(host: :duckdb)
    db.extension :settable
    db
  end
end
