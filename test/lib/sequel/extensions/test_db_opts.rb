require_relative '../../../test_helper'
require 'sequel'
require 'sequel/extensions/db_opts'

class TestDbOpts < Minitest::Test
  def with_fake_database_type_and_options(db_type, opts = {})
    db = Minitest::Mock.new
    db.expect :extension, nil, [:settable]
    db.expect :database_type, db_type
    db.expect :opts, opts
    yield db
    db.verify
  end

  def with_conn
    conn = Minitest::Mock.new
    yield conn
    conn.verify
  end

  def test_should_detect_options_for_appropriate_db
    with_fake_database_type_and_options(:postgres, postgres_db_opt_flim: :flam) do |db|
      with_conn do |conn|
        returns = ["SET flim=flam"]
        db.expect :set_sql, returns, [flim: :flam]
        conn.expect :execute, nil, returns
        db_opts = Sequel::DbOpts::DbOptions.new(db)
        db_opts.apply(conn)
      end
    end
  end

  def test_should_ignore_options_for_inappropriate_db
    with_fake_database_type_and_options(:postgres, postgres_db_opt_flim: :flam, other_db_opt_foo: :bar) do |db|
      with_conn do |conn|
        returns = ["SET flim=flam"]
        db.expect :set_sql, returns, [flim: :flam]
        conn.expect :execute, nil, returns
        db_opts = Sequel::DbOpts::DbOptions.new(db)
        db_opts.apply(conn)
      end
    end
  end

  def test_should_ignore_non_db_opts
    with_fake_database_type_and_options(:postgres, postgres_flim: :flam) do |db|
      with_conn do |conn|
        returns = []
        db.expect :set_sql, returns, [{}]
        db_opts = Sequel::DbOpts::DbOptions.new(db)
        db_opts.apply(conn)
      end
    end
  end

  def test_should_properly_quote_awkward_values
    with_fake_database_type_and_options(:postgres, postgres_db_opt_str: "hello there", postgres_db_opt_hyphen: "i-like-hyphens-though-they-are-dumb") do |db|
      with_conn do |conn|
        db.expect :literal, "hello there", ["hello there"]
        db.expect :literal, "i-like-hyphens-though-they-are-dumb", ["i-like-hyphens-though-they-are-dumb"]
        returns = ["SET str='hello there'", "SET hyphens='i-like-hyphens-though-they-are-dumb'"]
        db.expect :set_sql, returns, [{str: "hello there", hyphen: "i-like-hyphens-though-they-are-dumb"}]
        returns.each do |stmt|
          conn.expect :execute, nil, [stmt]
        end
        db_opts = Sequel::DbOpts::DbOptions.new(db)
        db_opts.apply(conn)
      end
    end
  end
end

