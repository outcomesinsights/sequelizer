require 'minitest/autorun'
require_relative '../../lib/sequelizer/yaml_config'


class TestYamlConfig < Minitest::Test
  def setup
    @yaml_config = Sequelizer::YamlConfig.new
  end

  def test_loads_from_yaml_file_if_present
    mock = Minitest::Mock.new
    file_mock = Minitest::Mock.new

    Sequelizer::YamlConfig.send(:const_set, :Psych, mock)

    mock.expect :load_file, { 'adapter' => 'sqlite' }, [file_mock]
    file_mock.expect :exist?, true

    @yaml_config.stub :config_file, file_mock do
      assert_equal({ 'adapter' => 'sqlite' }, @yaml_config.options)
    end

    file_mock.verify
    mock.verify
    Sequelizer::YamlConfig.send(:remove_const, :Psych)
  end

  def test_loads_by_environment_if_present
    file_mock = Minitest::Mock.new
    file_mock.expect :exist?, true
    @yaml_config.stub :config_file, file_mock do
      @yaml_config.stub :config, {'development' => { 'adapter' => 'sqlite' }} do
        assert_equal({ 'adapter' => 'sqlite' }, @yaml_config.options)
      end
    end
    file_mock.verify
  end

  def test_environment_checks_environment_variables
    env_mock = Minitest::Mock.new
    env_mock.expect :[], nil, ['SEQUELIZER_ENV']
    env_mock.expect :[], nil, ['RAILS_ENV']
    env_mock.expect :[], nil, ['RACK_ENV']

    Sequelizer::YamlConfig.send(:const_set, :ENV, env_mock)
    assert_equal 'development', @yaml_config.environment
    Sequelizer::YamlConfig.send(:remove_const, :ENV)

    env_mock.verify
  end
end
