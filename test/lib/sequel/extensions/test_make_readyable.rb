require_relative '../../../test_helper'
require 'fileutils'
require 'tmpdir'
require 'pathname'
require 'sequel'
require 'sequel/extensions/make_readyable'

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
        %i[a b]
      when :schema3
        %i[a b]
      end
    end
  end

  def test_should_call_use_schema
    @db.make_ready(use_schema: :some_schema)

    assert_equal(['USE `some_schema`'], @db.sqls)
  end

  def test_should_create_views_based_on_tables_in_search_paths
    @db.make_ready(search_path: %i[schema1 schema2 schema3])

    assert_equal([
                   'CREATE TEMPORARY VIEW `a` AS SELECT * FROM `schema1`.`a`',
                   'CREATE TEMPORARY VIEW `b` AS SELECT * FROM `schema2`.`b`',
                 ], @db.sqls)
  end

  def test_should_create_views_based_on_tables_in_search_paths_passed_as_strings
    @db.make_ready(search_path: %w[schema1 schema2 schema3])

    assert_equal([
                   'CREATE TEMPORARY VIEW `a` AS SELECT * FROM `schema1`.`a`',
                   'CREATE TEMPORARY VIEW `b` AS SELECT * FROM `schema2`.`b`',
                 ], @db.sqls)
  end

  def test_should_create_views_based_on_tables_in_search_paths_accepts_except
    @db.make_ready(search_path: %i[schema1 schema2 schema3], except: :a)

    assert_equal([
                   'CREATE TEMPORARY VIEW `b` AS SELECT * FROM `schema2`.`b`',
                 ], @db.sqls)
  end

  def test_should_create_views_based_on_tables_in_search_paths_accepts_only
    @db.make_ready(search_path: %i[schema1 schema2 schema3], only: :b)

    assert_equal([
                   'CREATE TEMPORARY VIEW `b` AS SELECT * FROM `schema2`.`b`',
                 ], @db.sqls)
  end

  def test_should_create_views_based_on_path
    dir = Pathname.new(Dir.mktmpdir)
    a_file = dir + 'a.parquet'
    b_file = dir + 'b.parquet'
    FileUtils.touch(a_file.to_s)
    FileUtils.touch(b_file.to_s)

    @db.make_ready(search_path: [:schema1, a_file, b_file, :schema2])
    sqls = @db.sqls.dup

    assert_equal('CREATE TEMPORARY VIEW `a` AS SELECT * FROM `schema1`.`a`', sqls[0])
    assert_match(%r{CREATE TEMPORARY VIEW `b` USING parquet OPTIONS \('path'='/tmp/[^/]+/b.parquet'\)}, sqls[1])
  end

  def test_should_create_views_format_based_on_path
    dir = Pathname.new(Dir.mktmpdir)
    a_file = dir + 'a.parquet'
    b_file = dir + 'b.delta'
    c_file = dir + 'c.csv'
    FileUtils.touch(a_file.to_s)
    FileUtils.touch(b_file.to_s)
    FileUtils.touch(c_file.to_s)

    @db.make_ready(search_path: [a_file, b_file, c_file])
    sqls = @db.sqls.dup

    assert_match(%r{CREATE TEMPORARY VIEW `a` USING parquet OPTIONS \('path'='/tmp/[^/]+/a.parquet'\)}, sqls[0])
    assert_match(%r{CREATE TEMPORARY VIEW `b` USING delta OPTIONS \('path'='/tmp/[^/]+/b.delta'\)}, sqls[1])
    assert_match(%r{CREATE TEMPORARY VIEW `c` USING csv OPTIONS \('path'='/tmp/[^/]+/c.csv'\)}, sqls[2])
  end

  def test_should_create_a_single_view_if_multiple_files_have_the_same_name
    dir = Pathname.new(Dir.mktmpdir)
    a_file = dir + 'a.parquet'
    b_file = dir + 'a.delta'
    c_file = dir + 'a.csv'
    FileUtils.touch(a_file.to_s)
    FileUtils.touch(b_file.to_s)
    FileUtils.touch(c_file.to_s)

    @db.make_ready(search_path: [a_file, b_file, c_file])
    sqls = @db.sqls.dup

    assert_equal(1, sqls.size)
    assert_match(%r{CREATE TEMPORARY VIEW `a` USING parquet OPTIONS \('path'='/tmp/[^/]+/a.parquet'\)}, sqls[0])
    refute_match(%r{CREATE TEMPORARY VIEW `a` USING delta OPTIONS \('path'='/tmp/[^/]+/a.delta'\)}, sqls[1])
    refute_match(%r{CREATE TEMPORARY VIEW `a` USING csv OPTIONS \('path'='/tmp/[^/]+/a.csv'\)}, sqls[2])
  end

  def test_should_create_a_single_view_if_multiple_files_have_the_same_name_and_are_in_different_directories
    dir = Pathname.new(Dir.mktmpdir)
    a_file = dir / 'one' / 'a.parquet'
    b_file = dir / 'two' / 'a.delta'
    c_file = dir / 'three' / 'a.csv'
    FileUtils.mkdir_p(a_file.dirname)
    FileUtils.mkdir_p(b_file.dirname)
    FileUtils.mkdir_p(c_file.dirname)
    FileUtils.touch(a_file.to_s)
    FileUtils.touch(b_file.to_s)
    FileUtils.touch(c_file.to_s)

    @db.make_ready(search_path: [a_file, b_file, c_file])
    sqls = @db.sqls.dup

    assert_equal(1, sqls.size)
    assert_match(%r{CREATE TEMPORARY VIEW `a` USING parquet OPTIONS \('path'='/tmp/[^/]+/one/a.parquet'\)}, sqls[0])
    refute_match(%r{CREATE TEMPORARY VIEW `a` USING delta OPTIONS \('path'='/tmp/[^/]+/two/a.delta'\)}, sqls[1])
    refute_match(%r{CREATE TEMPORARY VIEW `a` USING csv OPTIONS \('path'='/tmp/[^/]+/three/a.csv'\)}, sqls[2])
  end

  def test_should_create_view_from_compact_style_path
    dir = Pathname.new(Dir.mktmpdir)
    a_file = dir / 'one' / 'a.parquet'
    b_file = dir / 'two' / 'b.delta'
    c_file = dir / 'three' / 'c.csv'
    FileUtils.mkdir_p(a_file.dirname)
    FileUtils.mkdir_p(b_file.dirname)
    FileUtils.mkdir_p(c_file.dirname)
    FileUtils.touch(a_file.to_s)
    FileUtils.touch(b_file.to_s)
    FileUtils.touch(c_file.to_s)

    @db.make_ready(search_path: [Dir["#{dir}/{one,two,three}"].map { |path| Pathname.new(path).glob('*') }])
    sqls = @db.sqls.dup

    assert_equal(3, sqls.size)
    assert_match(%r{CREATE TEMPORARY VIEW `a` USING parquet OPTIONS \('path'='/tmp/[^/]+/one/a.parquet'\)}, sqls[0])
    assert_match(%r{CREATE TEMPORARY VIEW `b` USING delta OPTIONS \('path'='/tmp/[^/]+/two/b.delta'\)}, sqls[1])
    assert_match(%r{CREATE TEMPORARY VIEW `c` USING csv OPTIONS \('path'='/tmp/[^/]+/three/c.csv'\)}, sqls[2])
  end

  def test_should_create_view_from_compact_style_path_with_multiple_files
    dir = Pathname.new(Dir.mktmpdir)
    a_file = dir / 'one' / 'a.parquet'
    b_file = dir / 'two' / 'a.delta'
    c_file = dir / 'three' / 'a.csv'
    FileUtils.mkdir_p(a_file.dirname)
    FileUtils.mkdir_p(b_file.dirname)
    FileUtils.mkdir_p(c_file.dirname)
    FileUtils.touch(a_file.to_s)
    FileUtils.touch(b_file.to_s)
    FileUtils.touch(c_file.to_s)

    @db.make_ready(search_path: [Dir["#{dir}/{one,two,three}"].map { |path| Pathname.new(path).glob('*') }])
    sqls = @db.sqls.dup

    assert_equal(1, sqls.size)
    assert_match(%r{CREATE TEMPORARY VIEW `a` USING parquet OPTIONS \('path'='/tmp/[^/]+/one/a.parquet'\)}, sqls[0])
    refute_match(%r{CREATE TEMPORARY VIEW `a` USING delta OPTIONS \('path'='/tmp/[^/]+/two/a.delta'\)}, sqls[1])
    refute_match(%r{CREATE TEMPORARY VIEW `a` USING csv OPTIONS \('path'='/tmp/[^/]+/three/a.csv'\)}, sqls[2])
  end

  def test_duckdb_external_file_support
    # Test DuckDB - uses read_* functions for external files
    duckdb_db = Sequel.mock
    duckdb_db.extension :make_readyable
    def duckdb_db.database_type
      :duckdb
    end

    dir = Pathname.new(Dir.mktmpdir)
    parquet_file = dir / 'test.parquet'
    csv_file = dir / 'test.csv'
    json_file = dir / 'test.json'
    FileUtils.touch(parquet_file.to_s)
    FileUtils.touch(csv_file.to_s)
    FileUtils.touch(json_file.to_s)

    # Test parquet file
    duckdb_db.make_ready(search_path: [parquet_file])

    assert_match(/CREATE VIEW \w*test\w* AS SELECT \* FROM read_parquet\('.*test\.parquet'\)/, duckdb_db.sqls.last)

    # Test CSV file
    duckdb_db.sqls.clear
    duckdb_db.make_ready(search_path: [csv_file])

    assert_match(/CREATE VIEW \w*test\w* AS SELECT \* FROM read_csv_auto\('.*test\.csv'\)/, duckdb_db.sqls.last)

    # Test JSON file
    duckdb_db.sqls.clear
    duckdb_db.make_ready(search_path: [json_file])

    assert_match(/CREATE VIEW \w*test\w* AS SELECT \* FROM read_json_auto\('.*test\.json'\)/, duckdb_db.sqls.last)
  end

  def test_unsupported_file_format_for_duckdb
    # Test unsupported file format for DuckDB
    duckdb_db = Sequel.mock
    duckdb_db.extension :make_readyable
    def duckdb_db.database_type
      :duckdb
    end

    dir = Pathname.new(Dir.mktmpdir)
    orc_file = dir / 'test.orc'
    FileUtils.touch(orc_file.to_s)

    error = assert_raises(Sequel::Error) do
      duckdb_db.make_ready(search_path: [orc_file])
    end
    assert_match(/Unsupported file format 'orc' for DuckDB/, error.message)
  end

  def test_duckdb_directory_support
    # Test DuckDB with directory paths (globbing)
    duckdb_db = Sequel.mock
    duckdb_db.extension :make_readyable
    def duckdb_db.database_type
      :duckdb
    end

    # Mock directory? to return true
    dir = Pathname.new(Dir.mktmpdir)
    def dir.directory?
      true
    end

    file_sourcerer = Sequel::ReadyMaker::FileSourcerer.new(duckdb_db, dir)

    # Override format to return parquet
    def file_sourcerer.format
      'parquet'
    end

    # For directory support, DuckDB should use globbing pattern
    file_sourcerer.create_view(:test_table)

    assert_match(%r{CREATE VIEW \w*test_table\w* AS SELECT \* FROM read_parquet\('.*/\*\*/\*\.parquet'\)},
                 duckdb_db.sqls.last)
  end

end
