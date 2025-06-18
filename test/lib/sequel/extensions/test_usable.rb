require_relative '../../../test_helper'
require 'sequel'
require 'sequel/extensions/usable'

class TestUsable < Minitest::Test

  def test_should_call_use
    db = Sequel.mock(host: :sqlite)
    db.extension :usable
    db.use(:some_schema)

    assert_equal(['USE `some_schema`'], db.sqls)
  end

end
