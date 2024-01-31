require_relative "../../../test_helper"
require "fileutils"
require "pathname"
require "sequel"
require "sequel/extensions/make_readyable"

class TestUsable < Minitest::Test
  def setup
    # These features are mostly intended for Spark, but sqlite is a close enough
    # mock that we'll just roll with it
    @db = Sequel.mock(host: :spark)
    @db.extension :make_readyable
    def @db.tables(opts = {})
      case opts[:schema]
      when :schema1
        [:a]
      when :schema2
        [:a, :b]
      when :schema3
        [:a, :b]
      end
    end
  end

  def test_should_call_use_schema
    @db.make_ready(use_schema: :some_schema)
    assert_equal(["USE `some_schema`"], @db.sqls)
  end

  def test_should_create_views_based_on_tables_in_search_paths
    @db.make_ready(search_path: [:schema1, :schema2, :schema3])
    assert_equal([
      "CREATE TEMPORARY VIEW `a` AS SELECT * FROM `schema1`.`a`",
      "CREATE TEMPORARY VIEW `b` AS SELECT * FROM `schema2`.`b`"
    ], @db.sqls)
  end

  def test_should_create_views_based_on_tables_in_search_paths_accepts_except
    @db.make_ready(search_path: [:schema1, :schema2, :schema3], except: :a)
    assert_equal([
      "CREATE TEMPORARY VIEW `b` AS SELECT * FROM `schema2`.`b`"
    ], @db.sqls)
  end

  def test_should_create_views_based_on_tables_in_search_paths_accepts_only
    @db.make_ready(search_path: [:schema1, :schema2, :schema3], only: :b)
    assert_equal([
      "CREATE TEMPORARY VIEW `b` AS SELECT * FROM `schema2`.`b`"
    ], @db.sqls)
  end

  def test_should_create_views_based_on_path
    dir = Pathname.new(Dir.mktmpdir)
    a_file = dir + "a.parquet"
    b_file = dir + "b.parquet"
    FileUtils.touch(a_file.to_s)
    FileUtils.touch(b_file.to_s)

    @db.make_ready(search_path: [:schema1, a_file, b_file, :schema2])
    sqls = @db.sqls.dup
    assert_equal("CREATE TEMPORARY VIEW `a` AS SELECT * FROM `schema1`.`a`", sqls[0])
    assert_match(%r{CREATE TEMPORARY VIEW `b` USING parquet OPTIONS \('path'='/tmp/[^/]+/b.parquet'\)}, sqls[1])
  end

  def test_should_create_views_format_based_on_path
    dir = Pathname.new(Dir.mktmpdir)
    a_file = dir + "a.parquet"
    b_file = dir + "b.delta"
    c_file = dir + "c.csv"
    FileUtils.touch(a_file.to_s)
    FileUtils.touch(b_file.to_s)
    FileUtils.touch(c_file.to_s)

    @db.make_ready(search_path: [a_file, b_file, c_file])
    sqls = @db.sqls.dup
    assert_match(%r{CREATE TEMPORARY VIEW `a` USING parquet OPTIONS \('path'='/tmp/[^/]+/a.parquet'\)}, sqls[0])
    assert_match(%r{CREATE TEMPORARY VIEW `b` USING delta OPTIONS \('path'='/tmp/[^/]+/b.delta'\)}, sqls[1])
    assert_match(%r{CREATE TEMPORARY VIEW `c` USING csv OPTIONS \('path'='/tmp/[^/]+/c.csv'\)}, sqls[2])
  end
end

