require_relative "../../test_helper"
require "tmpdir"
require "sequelizer"

class TestDatasetDb < Minitest::Test
  SCHEMA = "synpuf".freeze

  def setup
    @root = Pathname(Dir.mktmpdir("sequelizer-dataset-db"))
  end

  def teardown
    Sequelizer.close_dataset_dbs
    FileUtils.rm_rf(@root)
  end

  # A small GDM dataset: the patients table in schema +schema+ of the one
  # DuckDB file in <root>/<schema>/.
  def make_dataset(schema = SCHEMA, file_name: "gdm.duckdb")
    build_dataset_file(@root.join(schema, file_name), schema)
  end

  # Writes a DuckDB file at +file+ whose schema +schema+ holds the patients
  # table with +rows+ patients.
  def build_dataset_file(file, schema = SCHEMA, rows: 2)
    file.dirname.mkpath
    db = Sequel.connect(adapter: :duckdb, database: file.to_s)
    db.create_schema(schema)
    db.create_table(Sequel.qualify(schema, :patients)) do
      Bignum :id, primary_key: true
      Bignum :gender_concept_id
      Date :birth_date
    end
    db[Sequel.qualify(schema, :patients)].import(%i[id gender_concept_id birth_date],
                                                 (1..rows).map { |id| [ id, 8507, Date.new(1950, 1, id) ] })
    db.disconnect
    file
  end

  def directory_url
    "duckdb://#{@root}"
  end

  def dataset_db(**)
    Sequelizer.dataset_db(**)
  end

  def setting(db, name)
    db.get(Sequel.function(:current_setting, name))
  end

  def test_a_directory_url_reads_a_dataset_table_without_a_schema_prefix
    make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)

    assert_equal [ 1, 2 ], db[:patients].order(:id).select_map(:id)
  end

  def test_a_file_url_attaches_that_file_directly
    file = make_dataset
    db = dataset_db(url: "duckdb://#{file}", schema: SCHEMA)

    assert_equal 2, db[:patients].count
  end

  def test_the_same_url_and_schema_return_the_same_connection
    make_dataset

    assert_same dataset_db(url: directory_url, schema: SCHEMA), dataset_db(url: directory_url, schema: SCHEMA.to_sym)
  end

  def test_urls_for_one_dataset_file_return_the_same_connection
    file = make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)

    assert_same db, dataset_db(url: "#{directory_url}/", schema: SCHEMA)
    assert_same db, dataset_db(url: "duckdb://#{file}", schema: SCHEMA)
  end

  def test_other_settings_under_another_url_for_one_file_raise
    file = make_dataset
    dataset_db(url: directory_url, schema: SCHEMA, memory_limit: "1GiB")
    error = assert_raises(Sequelizer::DatasetSettingsConflictError) do
      Sequelizer.dataset_db(url: "duckdb://#{file}", schema: SCHEMA, memory_limit: "2GiB")
    end

    assert_includes error.message, file.realpath.to_s.inspect
  end

  def test_another_schema_gets_another_connection
    make_dataset
    make_dataset("seer")

    refute_same dataset_db(url: directory_url, schema: SCHEMA), dataset_db(url: directory_url, schema: "seer")
  end

  def test_concurrent_calls_return_one_connection
    make_dataset
    dbs = Array.new(4) { Thread.new { dataset_db(url: directory_url, schema: SCHEMA) } }.map(&:value)

    assert_equal 1, dbs.uniq(&:object_id).size
  end

  def test_the_duckdb_settings_show_in_current_setting
    make_dataset
    temp = @root.join("spill").to_s
    db = dataset_db(url: directory_url, schema: SCHEMA, memory_limit: "1GiB", temp_directory: temp,
                    max_temp_directory_size: "2GiB", threads: 2)

    assert_equal "1.0 GiB", setting(db, "memory_limit")
    assert_equal temp, setting(db, "temp_directory")
    assert_equal "2.0 GiB", setting(db, "max_temp_directory_size")
    assert_equal 2, setting(db, "threads")
  end

  def test_a_write_to_the_dataset_fails
    make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)

    insert = assert_raises(Sequel::DatabaseError) { db[:patients].insert(id: 3, gender_concept_id: 8507) }
    delete = assert_raises(Sequel::DatabaseError) { db[Sequel.qualify(SCHEMA, :patients)].delete }

    assert_match(/"INSERT" on database "dataset" which is attached in read-only mode/, insert.message)
    assert_match(/"DELETE" on database "dataset" which is attached in read-only mode/, delete.message)
    assert_equal 2, db[:patients].count
  end

  def test_a_create_without_a_catalog_goes_to_the_in_memory_database
    make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)
    db.create_table(:scratch) { Integer :n }
    db[:scratch].insert(n: 1)

    assert_equal 1, db[Sequel.qualify(Sequel.qualify(:memory, :main), :scratch)].count
  end

  def test_a_created_table_hides_the_dataset_table_of_the_same_name_for_every_thread
    make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)
    db.create_table(:patients) { Integer :n }

    assert_equal 0, Thread.new { db[:patients].count }.value
    assert_equal 2, db[Sequel.qualify(SCHEMA, :patients)].count
  end

  def test_every_pool_connection_gets_the_dataset_and_the_search_path
    make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)
    db.disconnect

    assert_equal 2, db[:patients].count
  end

  def test_a_replaced_dataset_file_is_read_only_after_close_dataset_dbs
    file = make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)
    db[:patients].count
    File.rename(build_dataset_file(@root.join("replacement.duckdb"), rows: 5), file)
    db.disconnect

    assert_equal 2, db[:patients].count

    Sequelizer.close_dataset_dbs
    fresh = dataset_db(url: directory_url, schema: SCHEMA)

    refute_same db, fresh
    assert_equal 5, fresh[:patients].count
  end

  def test_sequel_does_not_keep_a_reference_to_a_dataset_connection
    make_dataset

    refute_includes Sequel::DATABASES, dataset_db(url: directory_url, schema: SCHEMA)
  end

  def test_readonly_false_raises
    error = assert_raises(ArgumentError) { Sequelizer.dataset_db(url: directory_url, schema: SCHEMA, readonly: false) }

    assert_match(/read-write .* not supported yet/, error.message)
  end

  def test_other_settings_for_a_cached_connection_raise
    make_dataset
    dataset_db(url: directory_url, schema: SCHEMA, memory_limit: "1GiB")
    error = assert_raises(Sequelizer::DatasetSettingsConflictError) do
      Sequelizer.dataset_db(url: directory_url, schema: SCHEMA, memory_limit: "2GiB")
    end

    assert_includes error.message, { "memory_limit" => "1GiB" }.inspect
    assert_includes error.message, { "memory_limit" => "2GiB" }.inspect
  end

  def test_a_url_that_is_not_duckdb_raises
    assert_raises(Sequelizer::UnsupportedDatasetURLError) do
      Sequelizer.dataset_db(url: "postgres://localhost/gdm", schema: SCHEMA)
    end
  end

  def test_a_missing_dataset_directory_raises
    error = assert_raises(Sequelizer::MissingDatasetError) { Sequelizer.dataset_db(url: directory_url, schema: SCHEMA) }

    assert_includes error.message, "holds 0"
  end

  def test_a_url_path_that_is_neither_a_file_nor_a_directory_raises
    make_dataset
    missing = @root.join(SCHEMA, "gdmm.duckdb")
    error = assert_raises(Sequelizer::MissingDatasetError) do
      Sequelizer.dataset_db(url: "duckdb://#{missing}", schema: SCHEMA)
    end

    assert_equal "#{missing} is neither a DuckDB file nor a directory, so it cannot hold the dataset #{SCHEMA}",
                 error.message
  end

  def test_a_dataset_directory_with_two_duckdb_files_raises
    make_dataset
    make_dataset(file_name: "other.duckdb")

    assert_raises(Sequelizer::MissingDatasetError) { Sequelizer.dataset_db(url: directory_url, schema: SCHEMA) }
  end

  def test_directory_url_is_false_for_an_existing_file
    file = make_dataset

    assert Sequelizer::DuckDBDataset.directory_url?(directory_url)
    refute Sequelizer::DuckDBDataset.directory_url?("duckdb://#{file}")
    refute Sequelizer::DuckDBDataset.directory_url?("postgres://localhost/gdm")
  end
end
