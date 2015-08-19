require_relative '../test_helper'
require_relative '../../lib/sequelizer/yaml_config'


class TestYamlConfig < Minitest::Test
  def setup
    @yaml_config = Sequelizer::YamlConfig.new
  end

  def test_loads_from_yaml_file_if_present
    mock = Minitest::Mock.new
    file_mock = Minitest::Mock.new

    stub_const(Sequelizer::YamlConfig, :Psych, mock) do
      mock.expect :load_file, { 'adapter' => 'sqlite' }, [file_mock]
      file_mock.expect :exist?, true

      @yaml_config.stub :config_file, file_mock do
        assert_equal({ 'adapter' => 'sqlite' }, @yaml_config.options)
      end

      file_mock.verify
      mock.verify
    end
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

  def test_options_default_to_empty_hash
    assert_equal(@yaml_config.options, {})
  end

  def test_environment_checks_environment_variables
    env_mock = Minitest::Mock.new
    env_mock.expect :[], nil, ['SEQUELIZER_ENV']
    env_mock.expect :[], nil, ['RAILS_ENV']
    env_mock.expect :[], nil, ['RACK_ENV']

    stub_const(Sequelizer::YamlConfig, :ENV, env_mock) do
      assert_equal 'development', @yaml_config.environment
    end

    env_mock.verify
  end
end
