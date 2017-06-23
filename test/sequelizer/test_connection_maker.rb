require_relative '../test_helper'
require_relative '../../lib/sequelizer'

class TestConnectionMaker < Minitest::Test
  def setup
    @options = { 'adapter' => 'mock', "host" => "postgres" }
  end

  def test_accepts_options_as_params
    Sequelizer::YamlConfig.stub :user_config_path, Pathname.new('/completely/made/up/path/that/does/not/exist') do
      assert_equal :postgres, Sequelizer::ConnectionMaker.new(@options).connection.database_type
    end
  end

  def test_reads_options_from_yaml_config
    yaml_config = Minitest::Mock.new
    yaml_config.expect :options, @options
    yaml_config.expect :options, @options

    Sequelizer::YamlConfig.stub :new, yaml_config do
      assert_equal :postgres, Sequelizer::ConnectionMaker.new.connection.database_type
    end

    yaml_config.verify
  end

  def test_reads_options_from_env_config_if_no_yaml_config
    yaml_config = Minitest::Mock.new
    yaml_config.expect :options, {}
    yaml_config.expect :options, {}

    env_config = Minitest::Mock.new
    env_config.expect :options, @options

    Sequelizer::YamlConfig.stub :new, yaml_config do
      Sequelizer::EnvConfig.stub :new, env_config do
        assert_equal :postgres, Sequelizer::ConnectionMaker.new.connection.database_type
      end
    end

    env_config.verify
    yaml_config.verify
  end

  def test_applies_configuration_to_connection
    Sequelizer::YamlConfig.stub :user_config_path, Pathname.new('/completely/made/up/path/that/does/not/exist') do
      conn = Minitest::Mock.new
      conn.expect :database_type, :postgres
      conn.expect :run, nil, ["SET search_path = searchy"]
      @options.merge!(postgres_db_opt_search_path: "searchy")
      @options.merge!(impala_db_opt_search_path: "searchy2")
      Sequel.stub :connect, conn do
        Sequelizer::ConnectionMaker.new(@options).connection
      end
      conn.verify
    end
  end
end
