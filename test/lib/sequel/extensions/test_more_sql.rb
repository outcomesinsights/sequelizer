# frozen_string_literal: true

require 'test_helper'
require 'sequel'
require 'sequel/extensions/more_sql'

class TestMoreSql < Minitest::Test

  def setup
    @db = Sequel.mock
    @db.extension :more_sql
  end

  def test_create_schema_with_symbol_name
    @db.create_schema(:test_schema)

    sqls = @db.sqls

    assert_equal 1, sqls.length
    assert_equal 'CREATE SCHEMA test_schema', sqls.first
  end

  def test_create_schema_with_string_name
    @db.create_schema('my_schema')

    sqls = @db.sqls

    assert_equal 1, sqls.length
    assert_equal "CREATE SCHEMA 'my_schema'", sqls.first
  end

  def test_create_schema_with_if_not_exists_option
    @db.create_schema(:analytics, if_not_exists: true)

    sqls = @db.sqls

    assert_equal 1, sqls.length
    assert_equal 'CREATE SCHEMA IF NOT EXISTS analytics', sqls.first
  end

  def test_create_schema_without_if_not_exists_option
    @db.create_schema(:reports, if_not_exists: false)

    sqls = @db.sqls

    assert_equal 1, sqls.length
    assert_equal 'CREATE SCHEMA reports', sqls.first
  end

  def test_create_schema_with_empty_options
    @db.create_schema(:staging, {})

    sqls = @db.sqls

    assert_equal 1, sqls.length
    assert_equal 'CREATE SCHEMA staging', sqls.first
  end

  def test_create_schema_with_special_characters_in_name
    @db.create_schema('schema-with-dashes')

    sqls = @db.sqls

    assert_equal 1, sqls.length
    assert_equal "CREATE SCHEMA 'schema-with-dashes'", sqls.first
  end

  def test_create_schema_returns_nil
    result = @db.create_schema(:test)

    assert_nil result
  end

  def test_create_schema_multiple_calls
    @db.create_schema(:first_schema)
    @db.create_schema(:second_schema, if_not_exists: true)
    @db.create_schema('third_schema')

    sqls = @db.sqls

    assert_equal 3, sqls.length
    assert_equal 'CREATE SCHEMA first_schema', sqls[0]
    assert_equal 'CREATE SCHEMA IF NOT EXISTS second_schema', sqls[1]
    assert_equal "CREATE SCHEMA 'third_schema'", sqls[2]
  end

  def test_extension_registration
    assert_respond_to Sequel::Database, :extension

    db = Sequel.mock

    assert_respond_to db, :extension

    db.extension :more_sql

    assert_respond_to db, :create_schema
  end

  def test_create_schema_with_qualified_name
    @db.create_schema(Sequel[:public][:my_schema])

    sqls = @db.sqls

    assert_equal 1, sqls.length
    assert_match(/CREATE SCHEMA/, sqls.first)
  end

  def test_create_schema_with_identifier
    @db.create_schema(Sequel.identifier(:test_schema))

    sqls = @db.sqls

    assert_equal 1, sqls.length
    assert_equal 'CREATE SCHEMA test_schema', sqls.first
  end

  def test_create_schema_handles_nil_options
    @db.create_schema(:test_schema)

    sqls = @db.sqls

    assert_equal 1, sqls.length
    assert_equal 'CREATE SCHEMA test_schema', sqls.first
  end

  def test_private_create_schema_sql_method_not_accessible
    assert_raises(NoMethodError) do
      @db.create_schema_sql(:test, {})
    end
  end

end
