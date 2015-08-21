require_relative '../test_helper'
require_relative '../../lib/sequelizer/options'


class TestOptions < Minitest::Test
  def test_changes_postgresql_adapter_to_postgres
    options = Sequelizer::Options.new(Sequelizer::OptionsHash.new(adapter: 'postgresql'))

    assert_equal('postgres', options.adapter)
    assert_equal('postgres', options.to_hash[:adapter])
    assert_equal('postgres', options.to_hash['adapter'])
  end

  def test_finds_search_path_as_search_path
    options = Sequelizer::Options.new(Sequelizer::OptionsHash.new(adapter: 'postgres', search_path: 'path'))

    assert_equal('path', options.search_path)
  end

  def test_finds_schema_as_search_path
    options = Sequelizer::Options.new(Sequelizer::OptionsHash.new(adapter: 'postgres', schema: 'path'))

    assert_equal('path', options.search_path)
  end

  def test_finds_schema_search_path_as_search_path
    options = Sequelizer::Options.new(Sequelizer::OptionsHash.new(adapter: 'postgres', schema_search_path: 'path'))

    assert_equal('path', options.search_path)
  end

  def test_prefers_search_path_over_schema_search_path
    options = Sequelizer::Options.new(Sequelizer::OptionsHash.new(adapter: 'postgres', search_path: 'path', schema_search_path: 'path2'))

    assert_equal('path', options.search_path)
  end

  def test_returns_timeout_as_an_integer_even_if_given_string
    options = Sequelizer::Options.new({timeout: "30"})
    assert_equal(30, options.to_hash[:timeout])
  end

  def test_returns_a_hash_even_if_given_nil
    Sequelizer::YamlConfig.stub :user_config_path, Pathname.new('/completely/made/up/path/that/does/not/exist') do
      options = Sequelizer::Options.new
      assert_equal({}, options.to_hash)
    end
  end

  def test_handles_symbolized_search_path
    options = Sequelizer::Options.new(search_path: 'passed', adapter: 'postgres')
    assert_equal 'passed', options.search_path
  end
end

