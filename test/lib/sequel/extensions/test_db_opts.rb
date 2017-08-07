require_relative '../../../test_helper'
require 'sequel'
require 'sequel/extensions/db_opts'

class TestDbOpts < Minitest::Test
  def with_fake_database_type_and_options(db_type, opts = {})
    conn = Minitest::Mock.new
    conn.expect :extension, nil, [:settable]
    conn.expect :database_type, db_type
    conn.expect :opts, opts
    yield conn
    conn.verify
  end

  def test_should_detect_options_for_appropriate_db
    with_fake_database_type_and_options(:postgres, postgres_db_opt_flim: :flam) do |conn|
      conn.expect :set, nil, [flim: :flam]
      db_opts = Sequel::DbOpts::DbOptions.new(conn)
      db_opts.apply
    end
  end

  def test_should_ignore_options_for_inappropriate_db
    with_fake_database_type_and_options(:postgres, postgres_db_opt_flim: :flam, other_db_opt_foo: :bar) do |conn|
      conn.expect :set, nil, [flim: :flam]
      db_opts = Sequel::DbOpts::DbOptions.new(conn)
      db_opts.apply
    end
  end

  def test_should_ignore_non_db_opts
    with_fake_database_type_and_options(:postgres, postgres_flim: :flam) do |conn|
      conn.expect :set, nil, [{}]
      db_opts = Sequel::DbOpts::DbOptions.new(conn)
      db_opts.apply
    end
  end
end

