require_relative '../../test_helper'
require 'sequelizer/options'

class TestOptions < Minitest::Test

  def test_changes_postgresql_adapter_to_postgres
    options = Sequelizer::Options.new(Sequelizer::OptionsHash.new(adapter: 'postgresql'))

    assert_equal('postgres', options.adapter)
    assert_equal('postgres', options.to_hash[:adapter])
    assert_equal('postgres', options.to_hash['adapter'])
  end

  def test_finds_search_path_as_search_path
    options = Sequelizer::Options.new(Sequelizer::OptionsHash.new(adapter: 'postgres', search_path: 'path'))

    assert_equal('path', options.search_path)
  end

  def test_finds_schema_as_search_path
    options = Sequelizer::Options.new(Sequelizer::OptionsHash.new(adapter: 'postgres', schema: 'path'))

    assert_equal('path', options.search_path)
  end

  def test_finds_schema_search_path_as_search_path
    options = Sequelizer::Options.new(Sequelizer::OptionsHash.new(adapter: 'postgres', schema_search_path: 'path'))

    assert_equal('path', options.search_path)
  end

  def test_prefers_search_path_over_schema_search_path
    options = Sequelizer::Options.new(Sequelizer::OptionsHash.new(adapter: 'postgres', search_path: 'path',
                                                                  schema_search_path: 'path2'))

    assert_equal('path', options.search_path)
  end

  def test_returns_timeout_as_an_integer_even_if_given_string
    options = Sequelizer::Options.new({ timeout: '30' })

    assert_equal(30, options.to_hash[:timeout])
  end

  def test_returns_a_hash_even_if_given_nil
    Sequelizer::YamlConfig.stub :user_config_path, Pathname.new('/completely/made/up/path/that/does/not/exist') do
      options = Sequelizer::Options.new

      assert_equal(1, options.to_hash.length)
      assert_instance_of(Proc, options.to_hash[:after_connect])
    end
  end

  def test_handles_symbolized_search_path
    options = Sequelizer::Options.new(search_path: 'passed', adapter: 'postgres')

    assert_equal 'passed', options.search_path
  end

  def test_handles_existing_after_connect
    db = Sequel.mock(host: :postgres)
    conny = Minitest::Mock.new
    conny.expect :db, db
    conny.expect :db, db
    conny.expect :db, db

    procky = proc { |conn| conn.db[:table].to_a }

    options = Sequelizer::Options.new(after_connect: procky)
    options.to_hash[:after_connect].call(conny, :default, db)

    assert_equal(['SELECT * FROM "table"'], db.sqls)
  end

  def test_url_based_connection_processes_search_path
    options = Sequelizer::Options.new(
      Sequelizer::OptionsHash.new(url: 'postgres://localhost/mydb', search_path: 'my_schema'),
    )

    assert_equal('my_schema', options.search_path)
    assert_instance_of(Proc, options.to_hash[:after_connect])
  end

  def test_url_based_connection_processes_schema_as_search_path
    options = Sequelizer::Options.new(
      Sequelizer::OptionsHash.new(url: 'postgresql://localhost/mydb', schema: 'my_schema'),
    )

    assert_equal('my_schema', options.search_path)
  end

  def test_url_based_connection_skips_search_path_processing_for_non_postgres
    options = Sequelizer::Options.new(
      Sequelizer::OptionsHash.new(url: 'mysql2://localhost/mydb', search_path: 'my_schema'),
    )

    # search_path key remains but is NOT processed (no schema creation callback)
    assert_equal('my_schema', options.search_path)
    # adapter should not be normalized to 'postgres'
    assert_nil(options.adapter)
  end

  def test_handles_array_search_path
    options = Sequelizer::Options.new(
      Sequelizer::OptionsHash.new(adapter: 'postgres', search_path: %w[public my_schema]),
    )

    assert_equal(%w[public my_schema], options.search_path)
    assert_after_connect_sql(
      options,
      ['CREATE SCHEMA IF NOT EXISTS public',
       'CREATE SCHEMA IF NOT EXISTS my_schema',
       'SET search_path TO public, my_schema'],
    )
  end

  def test_handles_mixed_array_search_path
    options = Sequelizer::Options.new(
      Sequelizer::OptionsHash.new(adapter: 'postgres', search_path: ['public', 'schema_a, schema_b']),
    )

    assert_equal(['public', 'schema_a, schema_b'], options.search_path)
    assert_after_connect_sql(
      options,
      ['CREATE SCHEMA IF NOT EXISTS public',
       'CREATE SCHEMA IF NOT EXISTS schema_a',
       'CREATE SCHEMA IF NOT EXISTS schema_b',
       'SET search_path TO public, schema_a, schema_b'],
    )
  end

  def test_handles_string_search_path_in_after_connect
    options = Sequelizer::Options.new(
      Sequelizer::OptionsHash.new(adapter: 'postgres', search_path: 'public, my_schema'),
    )

    assert_after_connect_sql(
      options,
      ['CREATE SCHEMA IF NOT EXISTS public',
       'CREATE SCHEMA IF NOT EXISTS my_schema',
       'SET search_path TO public, my_schema'],
    )
  end

  def test_handles_extensions_passed_in
    options = Sequelizer::Options.new(extension_example_one: 1, extension_example_two: 1, not_an_extension_example: 1)

    assert_equal 1, options.to_hash[:not_an_extension_example]
    assert_includes options.extensions, :example_one, 'Failed to find example_one in extensions'
    assert_includes options.extensions, :example_two, 'Failed to find example_two in extensions'
  end

  private

  # Invokes the inner after_connect proc (the one that creates schemas and
  # sets search_path) via the make_ac wrapper, and asserts it produced the
  # expected SQL statements.
  def assert_after_connect_sql(options, expected_sqls)
    db = Sequel.mock(host: :postgres)
    raw_conn = db.synchronize { |c| c }
    options.to_hash[:after_connect].call(raw_conn, :default, db)

    assert_equal(expected_sqls, db.sqls)
  end

end
