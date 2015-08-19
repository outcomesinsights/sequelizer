require_relative '../test_helper'
require_relative '../../lib/sequelizer'

class TestConnectionMaker < Minitest::Test
  def setup
    @options = { 'adapter' => 'sqlite' }
    @sequel_mock = Minitest::Mock.new
    stub_const(Sequelizer::ConnectionMaker, :Sequel, @sequel_mock)
    @sequel_mock.expect :connect, :connection, [@options]
  end

  def teardown
    @sequel_mock.verify
    remove_stubbed_const(Sequelizer::ConnectionMaker, :Sequel)
  end

  def test_accepts_options_as_params
    assert_equal :connection, Sequelizer::ConnectionMaker.new(@options).connection
  end

  def test_reads_options_from_yaml_config
    yaml_config = Minitest::Mock.new
    yaml_config.expect :options, @options

    Sequelizer::YamlConfig.stub :new, yaml_config do
      assert_equal :connection, Sequelizer::ConnectionMaker.new.connection
    end

    yaml_config.verify
  end

  def test_reads_options_from_env_config_if_no_yaml_config
    yaml_config = Minitest::Mock.new
    yaml_config.expect :options, {}

    env_config = Minitest::Mock.new
    env_config.expect :options, @options

    Sequelizer::YamlConfig.stub :new, yaml_config do
      Sequelizer::EnvConfig.stub :new, env_config do
        assert_equal :connection, Sequelizer::ConnectionMaker.new.connection
      end
    end

    env_config.verify
    yaml_config.verify
  end
end
