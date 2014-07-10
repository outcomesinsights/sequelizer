require_relative '../test_helper'
require_relative '../../lib/sequelizer/env_config'


class TestEnvConfig < Minitest::Test
  def setup
    @env_config = Sequelizer::EnvConfig.new
  end
  def test_loads_dotenv
    mock = Minitest::Mock.new
    stub_const(Sequelizer::EnvConfig, :Dotenv, mock) do
      mock.expect :load, nil
      @env_config.options
      mock.verify
    end
  end

  def test_converts_sequelizer_vars_to_options
    ENV['SEQUELIZER_ADAPTER'] = 'sqlite'
    assert_equal({ 'adapter' => 'sqlite' }, @env_config.options)
    ENV.delete('SEQUELIZER_ADAPTER')
  end
end
