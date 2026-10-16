require_relative "../../test_helper"
require "sequelizer/options"

class TestOptions < Minitest::Test
  def test_changes_postgresql_adapter_to_postgres
    options = Sequelizer::Options.new({ adapter: "postgresql" })

    assert_equal("postgres", options.adapter)
    assert_equal("postgres", options.to_hash[:adapter])
  end

  def test_symbolizes_string_keys_at_every_depth
    options = Sequelizer::Options.new({ "adapter" => "mock", "ignore_yaml" => true, "ignore_env" => true,
                                        "servers" => { "read_only" => { "host" => "replica" } } })

    assert_equal("mock", options.to_hash[:adapter])
    assert_nil(options.to_hash["adapter"])
    assert_equal({ read_only: { host: "replica" } }, options.to_hash[:servers])
  end

  def test_finds_search_path_as_search_path
    options = Sequelizer::Options.new({ adapter: "postgres", search_path: "path" })

    assert_equal("path", options.search_path)
  end

  def test_finds_schema_as_search_path
    options = Sequelizer::Options.new({ adapter: "postgres", schema: "path" })

    assert_equal("path", options.search_path)
  end

  def test_finds_schema_search_path_as_search_path
    options = Sequelizer::Options.new({ adapter: "postgres", schema_search_path: "path" })

    assert_equal("path", options.search_path)
  end

  def test_prefers_search_path_over_schema_search_path
    options = Sequelizer::Options.new({ adapter: "postgres", search_path: "path", schema_search_path: "path2" })

    assert_equal("path", options.search_path)
  end

  def test_passed_schema_wins_over_search_path_from_env
    with_sources(env: { "search_path" => "from_env" }) do
      options = Sequelizer::Options.new(adapter: "postgres", schema: "passed")

      assert_equal("passed", options.search_path)
      assert_nil(options.to_hash[:schema])
    end
  end

  def test_passed_schema_search_path_wins_over_search_path_from_yaml
    with_sources(yaml: { "search_path" => "from_yaml" }) do
      options = Sequelizer::Options.new(adapter: "postgres", schema_search_path: "passed")

      assert_equal("passed", options.search_path)
    end
  end

  def test_schema_from_env_wins_over_search_path_from_yaml
    with_sources(env: { "schema" => "from_env" }, yaml: { "adapter" => "postgres", "search_path" => "from_yaml" }) do
      assert_equal("from_env", Sequelizer::Options.new.search_path)
    end
  end

  def test_runs_search_path_setup_and_the_callers_after_connect
    calls = []
    [
      ->(conn) { calls << [ :one, conn.class ] },
      ->(conn, server) { calls << [ :two, conn.class, server ] }
    ].each do |user_after_connect|
      options = Sequelizer::Options.new(adapter: "postgres", search_path: "my_schema", after_connect: user_after_connect)
      db = Sequel.mock(host: :postgres)
      db.synchronize { |conn| options.to_hash[:after_connect].call(conn, :default) }

      assert_equal([ "CREATE SCHEMA IF NOT EXISTS my_schema", "SET search_path TO my_schema" ], db.sqls)
    end

    assert_equal([ [ :one, Sequel::Mock::Connection ], [ :two, Sequel::Mock::Connection, :default ] ], calls)
  end

  def test_returns_timeout_as_an_integer_even_if_given_string
    options = Sequelizer::Options.new({ timeout: "30" })

    assert_equal(30, options.to_hash[:timeout])
  end

  def test_returns_a_hash_even_if_given_nil
    Sequelizer::YamlConfig.stub :user_config_path, Pathname.new("/completely/made/up/path/that/does/not/exist") do
      options = Sequelizer::Options.new

      assert_kind_of(Hash, options.to_hash)
      assert_empty(options.to_hash)
    end
  end

  def test_handles_symbolized_search_path
    options = Sequelizer::Options.new(search_path: "passed", adapter: "postgres")

    assert_equal "passed", options.search_path
  end

  # Wrapping after_connect (to apply db_opts) is ConnectionMaker's job; see
  # TestConnectionMaker#test_calls_user_after_connect_procs_of_either_arity.
  def test_passes_existing_after_connect_through_unchanged
    procky = proc { |conn| conn.db[:table].to_a }

    options = Sequelizer::Options.new(after_connect: procky)

    assert_same(procky, options.to_hash[:after_connect])
  end

  def test_url_based_connection_processes_search_path
    options = Sequelizer::Options.new(
      { url: "postgres://localhost/mydb", search_path: "my_schema" },
    )

    assert_equal("my_schema", options.search_path)
    assert_instance_of(Proc, options.to_hash[:after_connect])
  end

  def test_treats_a_url_string_as_the_url_option
    options = Sequelizer::Options.new("postgres://localhost/mydb")

    assert_equal("postgres://localhost/mydb", options.to_hash[:url])
    assert_equal("postgres", options.adapter)
    assert_equal(Sequelizer::Options.new(url: "postgres://localhost/mydb").to_hash, options.to_hash)
  end

  def test_url_based_connection_processes_schema_as_search_path
    options = Sequelizer::Options.new(
      { url: "postgresql://localhost/mydb", schema: "my_schema" },
    )

    assert_equal("my_schema", options.search_path)
  end

  def test_url_based_connection_skips_search_path_processing_for_non_postgres
    options = Sequelizer::Options.new(
      { url: "mysql2://localhost/mydb", search_path: "my_schema" },
    )

    # search_path key remains but is NOT processed (no schema creation callback)
    assert_equal("my_schema", options.search_path)
    # adapter should not be normalized to 'postgres'
    assert_nil(options.adapter)
  end

  def test_handles_array_search_path
    options = Sequelizer::Options.new(
      { adapter: "postgres", search_path: %w[public my_schema] },
    )

    assert_equal(%w[public my_schema], options.search_path)
    assert_after_connect_sql(
      options,
      [ "CREATE SCHEMA IF NOT EXISTS public",
       "CREATE SCHEMA IF NOT EXISTS my_schema",
       "SET search_path TO public, my_schema" ],
    )
  end

  def test_handles_mixed_array_search_path
    options = Sequelizer::Options.new(
      { adapter: "postgres", search_path: [ "public", "schema_a, schema_b" ] },
    )

    assert_equal([ "public", "schema_a, schema_b" ], options.search_path)
    assert_after_connect_sql(
      options,
      [ "CREATE SCHEMA IF NOT EXISTS public",
       "CREATE SCHEMA IF NOT EXISTS schema_a",
       "CREATE SCHEMA IF NOT EXISTS schema_b",
       "SET search_path TO public, schema_a, schema_b" ],
    )
  end

  def test_handles_string_search_path_in_after_connect
    options = Sequelizer::Options.new(
      { adapter: "postgres", search_path: "public, my_schema" },
    )

    assert_after_connect_sql(
      options,
      [ "CREATE SCHEMA IF NOT EXISTS public",
       "CREATE SCHEMA IF NOT EXISTS my_schema",
       "SET search_path TO public, my_schema" ],
    )
  end

  def test_handles_extensions_passed_in
    options = Sequelizer::Options.new(extension_example_one: 1, extension_example_two: 1, not_an_extension_example: 1)

    assert_equal 1, options.to_hash[:not_an_extension_example]
    assert_includes options.extensions, :example_one, "Failed to find example_one in extensions"
    assert_includes options.extensions, :example_two, "Failed to find example_two in extensions"
  end

  private

  # Replaces both YAML sources and the env source with the given hashes.
  def with_sources(env: {}, yaml: {}, &)
    yaml_config = Sequelizer::YamlConfig.new
    env_config = Sequelizer::EnvConfig.new
    yaml_config.stub(:options, yaml) do
      env_config.stub(:options, env) do
        Sequelizer::YamlConfig.stub(:new, yaml_config) do
          Sequelizer::EnvConfig.stub(:new, env_config, &)
        end
      end
    end
  end

  # Invokes the after_connect proc that creates schemas and sets
  # search_path, and asserts it produced the expected SQL statements.
  def assert_after_connect_sql(options, expected_sqls)
    db = Sequel.mock(host: :postgres)
    raw_conn = db.synchronize { |c| c }
    options.to_hash[:after_connect].call(raw_conn)

    assert_equal(expected_sqls, db.sqls)
  end
end
