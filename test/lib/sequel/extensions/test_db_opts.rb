require_relative '../../../test_helper'
require 'sequel'
require 'sequel/extensions/db_opts'

class TestDbOpts < Minitest::Test
  def with_fake_database_type_and_options(db_type, opts = {})
    db = Sequel.mock
    db.define_singleton_method(:database_type){db_type}
    db.define_singleton_method(:opts){opts}
    db.extension :db_opts
    yield db
  end

  def sql_for(db_type, options)
    with_fake_database_type_and_options(db_type, options) do |db|
      db.synchronize do |conn|
        db.db_opts.apply(conn)
        return db.sqls
      end
    end
  end

  def test_should_detect_options_for_appropriate_db
    assert_equal(sql_for(:postgres, postgres_db_opt_flim: :flam), ["SET flim=flam"])
  end

  def test_should_ignore_options_for_inappropriate_db
    assert_equal(sql_for(:postgres, postgres_db_opt_flim: :flam, other_db_opt_foo: :bar), ["SET flim=flam"])
  end

  def test_should_ignore_non_db_opts
    assert_equal(sql_for(:postgres, postgres_flim: :flam), [])
  end

  def test_should_properly_quote_awkward_values
    assert_equal(sql_for(:postgres, postgres_db_opt_str: "hello there", postgres_db_opt_hyphen: "i-like-hyphens-though-they-are-dumb"),
      ["SET str='hello there'", "SET hyphen='i-like-hyphens-though-they-are-dumb'"])
  end
end

