require_relative '../../test_helper'
require 'sequelizer'

class TestConnectionMaker < Minitest::Test
  def setup
    @options = { 'adapter' => 'mock', "host" => "postgres" }
  end

  def test_accepts_options_as_params
    Sequelizer::YamlConfig.stub :user_config_path, Pathname.new('/completely/made/up/path/that/does/not/exist') do
      assert_equal :postgres, Sequelizer::ConnectionMaker.new(@options).connection.database_type
    end
  end

  def with_yaml_config(options = {})
    yaml_config = Minitest::Mock.new
    yaml_config.expect :options, options
    yaml_config.expect :options, options
    Sequelizer::YamlConfig.stub :new, yaml_config do
      yield
    end
    yaml_config.verify
  end

  def with_env_config(options = {})
    env_config = Minitest::Mock.new
    env_config.expect :options, options
    Sequelizer::EnvConfig.stub :new, env_config do
      yield
    end
    env_config.verify
  end

  def test_reads_options_from_yaml_config
    with_yaml_config(@options) do
      assert_equal :postgres, Sequelizer::ConnectionMaker.new.connection.database_type
    end
  end

  def test_applies_settings_if_given
    with_yaml_config(@options.merge(postgres_db_opt_flim: :flam)) do
      with_env_config do
        conn = Sequelizer::ConnectionMaker.new.connection
        conn.test_connection
        assert_equal(["SET flim=flam"], conn.sqls)
      end
    end
  end

  def test_applies_settings_for_all_connections_if_given
    with_yaml_config(@options.merge(postgres_db_opt_flim: :flam, max_connections: 2, preconnect: :concurrent)) do
      with_env_config do
        conn = Sequelizer::ConnectionMaker.new.connection
        conn.test_connection
        assert_equal(["SET flim=flam -- nil"] * 2, conn.sqls)
      end
    end
  end

  def test_reads_options_from_env_config_if_no_yaml_config
    with_yaml_config do
      with_env_config(@options) do
        assert_equal :postgres, Sequelizer::ConnectionMaker.new.connection.database_type
      end
    end
  end

  def test_applies_configuration_to_connection
    opts = @options.merge(postgres_db_opt_search_path: "searchy", impala_db_opt_search_path: "searchy2")
    with_yaml_config(opts) do
      conn = Sequelizer::ConnectionMaker.new.connection
      conn.test_connection
      assert_equal({ search_path: "searchy" }, conn.db_opts.to_hash)
      assert_equal(["SET search_path=searchy"], conn.db_opts.sql_statements)
    end
  end

  def test_applies_nothing_when_no_configuration
    Sequelizer::YamlConfig.stub :user_config_path, Pathname.new('/completely/made/up/path/that/does/not/exist') do
      conn = Sequelizer::ConnectionMaker.new(@options).connection
      conn.test_connection
      assert_equal({}, conn.db_opts.to_hash)
      assert_equal([], conn.db_opts.sql_statements)
    end
  end

  def test_applies_quotes_when_necessary
    Sequelizer::YamlConfig.stub :user_config_path, Pathname.new('/completely/made/up/path/that/does/not/exist') do
      @options.merge!(postgres_db_opt_search_path: "searchy,path")
      conn = Sequelizer::ConnectionMaker.new(@options).connection
      conn.test_connection
      assert_equal({ search_path: "'searchy,path'" }, conn.db_opts.to_hash)
      assert_equal(["SET search_path='searchy,path'"], conn.db_opts.sql_statements)
    end
  end

  def test_applies_extensions
    with_yaml_config(@options.merge(extension_error_sql: 1)) do
      assert Sequelizer::ConnectionMaker.new.connection.send(:instance_variable_get, "@loaded_extensions".to_sym).include?(:error_sql), "Extension wasn't set"
    end
  end
end
