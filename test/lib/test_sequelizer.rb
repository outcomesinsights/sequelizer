require_relative "../test_helper"
require "sequelizer"

class TestSequelizer < Minitest::Test
  URL = "mock://postgres"

  def setup
    @subject = Class.new { include Sequelizer }.new
  end

  # The project and user YAML files and the .env file must not leak into
  # these connections.
  def without_config_files(&)
    yaml_config = Sequelizer::YamlConfig.new
    env_config = Sequelizer::EnvConfig.new
    yaml_config.stub(:options, {}) do
      env_config.stub(:options, {}) do
        Sequelizer::YamlConfig.stub(:new, yaml_config) do
          Sequelizer::EnvConfig.stub(:new, env_config, &)
        end
      end
    end
  end

  def test_new_db_accepts_a_url_string
    without_config_files do
      assert_equal :postgres, @subject.new_db(URL).database_type
    end
  end

  def test_new_db_returns_the_cached_connection_for_a_url_string
    without_config_files do
      first = @subject.new_db(URL)

      assert_same first, @subject.new_db(URL)
    end
  end

  def test_a_url_string_shares_the_cache_with_the_url_option
    without_config_files do
      assert_same @subject.new_db(url: URL), @subject.new_db(URL)
      assert_same @subject.new_db(URL), @subject.find_cached(URL)
    end
  end

  def test_db_accepts_a_url_string
    without_config_files do
      assert_equal :postgres, @subject.db(URL).database_type
    end
  end

  def test_db_accepts_a_url_string_already_in_the_cache
    without_config_files do
      @subject.new_db(URL)

      assert_equal :postgres, @subject.db(URL).database_type
    end
  end

  def test_force_new_still_bypasses_the_cache_for_hash_options
    without_config_files do
      first = @subject.new_db(url: URL)

      refute_same first, @subject.new_db(url: URL, force_new: true)
    end
  end
end
