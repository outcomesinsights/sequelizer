require_relative '../../../test_helper'
require 'sequel'
require 'sequel/extensions/usable'

class TestUsable < Minitest::Test
  def test_should_detect_options_for_appropriate_db
    db = Sequel.mock(host: :sqlite)
    db.extension :usable
    db.use(:some_schema)
    assert_equal(db.sqls, ["USE `some_schema`"])
  end
end

