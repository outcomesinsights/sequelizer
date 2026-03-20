require_relative '../../../test_helper'
require 'sequel'
require 'sequel/extensions/funky'

class TestFunky < Minitest::Test

  def test_mock_duckdb_connection_uses_duckdb_functions
    db = Sequel.connect('mock://duckdb')

    db.extension :funky

    assert_instance_of Sequel::Funky::FunkyDuckDB, db.funky
    assert_includes db.literal(db.funky.hash(:foo, :bar)), 'concat'
  end

end
