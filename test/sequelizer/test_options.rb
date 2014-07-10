require_relative '../test_helper'
require_relative '../../lib/sequelizer/options'


class TestOptions < Minitest::Test
  def test_changes_postgresql_adapter_to_postgres
    options = Sequelizer::Options.new(Sequelizer::OptionsHash.new(adapter: 'postgresql'))

    assert_equal('postgres', options.adapter)
    assert_equal('postgres', options.to_hash[:adapter])
    assert_equal('postgres', options.to_hash['adapter'])
  end

  def test_finds_schema_as_search_path
    options = Sequelizer::Options.new(Sequelizer::OptionsHash.new(adapter: 'postgres', search_path: 'path'))

    assert_equal('path', options.schema_search_path)
  end

  def test_finds_schema_as_schema
    options = Sequelizer::Options.new(Sequelizer::OptionsHash.new(adapter: 'postgres', schema: 'path'))

    assert_equal('path', options.schema_search_path)
  end

  def test_finds_schema_as_schema_search_path
    options = Sequelizer::Options.new(Sequelizer::OptionsHash.new(adapter: 'postgres', schema_search_path: 'path'))

    assert_equal('path', options.schema_search_path)
  end

  def test_returns_a_hash_even_if_given_nil
    options = Sequelizer::Options.new
    assert_equal({}, options.to_hash)
  end
end

