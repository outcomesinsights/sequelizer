require_relative '../../../test_helper'
require 'sequel'
require 'sequel/extensions/settable'

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
    db.set(search_path: 'public')

    assert_equal(['SET search_path=public'], db.sqls)
  end

  def test_set_with_multiple_options
    db = Sequel.mock(host: :sqlite)
    db.extension :settable
    db.set(search_path: 'public', timezone: 'UTC')

    expected_sqls = ['SET search_path=public', 'SET timezone=UTC']

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
    db.set(work_mem: '256MB', statement_timeout: '30s')

    expected_sqls = ['SET work_mem=256MB', 'SET statement_timeout=30s']

    assert_equal expected_sqls, db.sqls
  end

  def test_set_with_numeric_values
    db = Sequel.mock(host: :sqlite)
    db.extension :settable
    db.set(port: 5432, max_connections: 100)

    expected_sqls = ['SET port=5432', 'SET max_connections=100']

    assert_equal expected_sqls, db.sqls
  end

  def test_set_with_boolean_values
    db = Sequel.mock(host: :sqlite)
    db.extension :settable
    db.set(autocommit: true, log_statement: false)

    expected_sqls = ['SET autocommit=true', 'SET log_statement=false']

    assert_equal expected_sqls, db.sqls
  end

  def test_set_with_nil_values
    db = Sequel.mock(host: :sqlite)
    db.extension :settable
    db.set(timezone: nil, search_path: nil)

    expected_sqls = ['SET timezone=', 'SET search_path=']

    assert_equal expected_sqls, db.sqls
  end

  def test_set_sql_private_method
    db = Sequel.mock(host: :sqlite)
    db.extension :settable

    refute_respond_to db, :set_sql
  end

  def test_multiple_set_calls
    db = Sequel.mock(host: :sqlite)
    db.extension :settable

    db.set(timezone: 'UTC')
    db.set(search_path: 'public')

    expected_sqls = ['SET timezone=UTC', 'SET search_path=public']

    assert_equal expected_sqls, db.sqls
  end

end
