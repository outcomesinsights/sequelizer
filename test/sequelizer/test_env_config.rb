require 'minitest/autorun'
require_relative '../../lib/sequelizer/env_config'


class TestEnvConfig < Minitest::Test
  def setup
    @env_config = Sequelizer::EnvConfig.new
  end
  def test_loads_dotenv
    mock = Minitest::Mock.new
    Sequelizer::EnvConfig.send(:const_set, :Dotenv, mock)
    mock.expect :load, nil
    @env_config.options
    mock.verify
    Sequelizer::EnvConfig.send(:remove_const, :Dotenv)
  end

  def test_converts_sequelizer_vars_to_options
    ENV['SEQUELIZER_ADAPTER'] = 'sqlite'
    assert_equal({ 'adapter' => 'sqlite' }, @env_config.options)
  end
end
