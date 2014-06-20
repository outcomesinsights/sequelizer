require 'minitest/autorun'
require_relative '../../lib/sequelizer'

Sequel = Minitest::Mock.new

class TestConnectionMaker < Minitest::Test
  def setup
    @options = { 'adapter' => 'sqlite' }
    @sequel_mock = Minitest::Mock.new
    Sequelizer::ConnectionMaker.send(:const_set, :Sequel, @sequel_mock)
    @sequel_mock.expect :connect, :connection, [@options]
  end

  def teardown
    @sequel_mock.verify
    Sequelizer::ConnectionMaker.send(:remove_const, :Sequel)
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
    yaml_config.expect :options, nil

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
