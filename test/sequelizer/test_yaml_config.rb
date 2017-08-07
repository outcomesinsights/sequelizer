require_relative '../test_helper'
require_relative '../../lib/sequelizer/yaml_config'


class TestYamlConfig < Minitest::Test
  def setup
    @yaml_config = Sequelizer::YamlConfig.new
  end

  def with_empty_env
    env_mock = Minitest::Mock.new
    env_mock.expect :[], nil, ['SEQUELIZER_ENV']
    env_mock.expect :[], nil, ['RAILS_ENV']
    env_mock.expect :[], nil, ['RACK_ENV']

    stub_const(Sequelizer::YamlConfig, :ENV, env_mock) do
      yield
    end

    env_mock.verify
  end

  def test_loads_from_yaml_file_if_present
    mock = Minitest::Mock.new
    file_mock = Minitest::Mock.new

    stub_const(Sequelizer::YamlConfig, :File, mock) do
      mock.expect :read, 'adapter: <%= "sqlite" %>', [file_mock]
      file_mock.expect :exist?, true

      @yaml_config.stub :config_file_path, file_mock do
        assert_equal({ 'adapter' => 'sqlite' }, @yaml_config.options)
      end

      file_mock.verify
      mock.verify
    end
  end

  def test_loads_by_environment_if_present
    file_mock = Minitest::Mock.new
    file_mock.expect :exist?, true
    @yaml_config.stub :config_file_path, file_mock do
      @yaml_config.stub :config, {'development' => { 'adapter' => 'sqlite' }} do
        with_empty_env do
          assert_equal({ 'adapter' => 'sqlite' }, @yaml_config.options)
        end
      end
    end
    file_mock.verify
  end

  def test_options_default_to_empty_hash
    assert_equal(@yaml_config.options, {})
  end

  def test_path_defaults_to_local_config
    assert_equal(@yaml_config.config_file_path, Pathname.pwd + "config" + "sequelizer.yml")
  end

  def test_path_can_be_fed_pathanem_from_initialize
    assert_equal(Sequelizer::YamlConfig.new(Pathname.new("~") + ".config").config_file_path, Pathname.new("~").expand_path + ".config")
  end

  def test_path_can_be_fed_string_from_initialize
    assert_equal(Sequelizer::YamlConfig.new("~/.config").config_file_path, Pathname.new("~").expand_path + ".config")
  end

  def test_local_is_current_directory
    assert_equal(Sequelizer::YamlConfig.local_config.config_file_path, Pathname.pwd + "config" + "sequelizer.yml")
  end

  def test_home_uses_home_directory
    assert_equal(Sequelizer::YamlConfig.user_config.config_file_path, Pathname.new("~").expand_path + ".config" + "sequelizer" + "database.yml")
  end

  def test_environment_checks_environment_variables
    with_empty_env do
      assert_equal 'development', @yaml_config.environment
    end
  end
end
