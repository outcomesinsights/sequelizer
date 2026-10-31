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
  def make_dataset(schema = SCHEMA, file_name: "gdm.duckdb", rows: 2)
    build_dataset_file(@root.join(schema, file_name), schema, rows:)
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

  def patients(schema = SCHEMA)
    Sequel[Sequelizer.dataset_catalog(schema)][schema.to_sym][:patients]
  end

  def setting(db, name)
    db.get(Sequel.function(:current_setting, name))
  end

  def dataset_catalogs(db)
    db.from(Sequel.function(:duckdb_databases)).where(Sequel.like(:database_name, "dataset_%"))
      .order(:database_name).select_map(:database_name)
  end

  def test_a_table_named_with_its_catalog_schema_and_table_reads_the_dataset
    make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)

    assert_equal [ 1, 2 ], db[patients].order(:id).select_map(:id)
  end

  def test_a_table_named_with_only_its_schema_reads_the_dataset_only_in_with_dataset
    make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)
    two_part = Sequel[SCHEMA.to_sym][:patients]

    assert_equal 2, Sequelizer.with_dataset(url: directory_url, schema: SCHEMA) { |d| d[two_part].count }
    error = assert_raises(Sequel::DatabaseError) { db[two_part].count }
    assert_match(/Catalog Error/, error.message)
  end

  def test_a_file_url_attaches_that_file_directly
    file = make_dataset
    db = dataset_db(url: "duckdb://#{file}", schema: SCHEMA)

    assert_equal 2, db[patients].count
  end

  def test_every_dataset_uses_the_one_database_of_the_process
    make_dataset
    make_dataset("seer", rows: 3)
    db = dataset_db(url: directory_url, schema: SCHEMA)

    assert_same db, dataset_db(url: directory_url, schema: "seer")
    assert_same db, dataset_db(url: directory_url, schema: SCHEMA.to_sym)
    assert_equal [ 2, 3 ], [ db[patients].count, db[patients("seer")].count ]
    assert_equal %w[dataset_seer dataset_synpuf], dataset_catalogs(db)
  end

  def test_urls_for_one_dataset_file_attach_it_once
    file = make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)
    dataset_db(url: "#{directory_url}/", schema: SCHEMA)
    dataset_db(url: "duckdb://#{file}", schema: SCHEMA)

    assert_equal %w[dataset_synpuf], dataset_catalogs(db)
  end

  def test_a_schema_from_another_file_raises
    make_dataset
    other = build_dataset_file(@root.join("other", SCHEMA, "gdm.duckdb"))
    dataset_db(url: directory_url, schema: SCHEMA)

    error = assert_raises(Sequelizer::DatasetSchemaConflictError) do
      Sequelizer.dataset_db(url: "duckdb://#{other}", schema: SCHEMA)
    end
    assert_includes error.message, other.realpath.to_s
  end

  def test_concurrent_calls_return_one_database
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

  def test_other_settings_for_any_dataset_raise
    make_dataset
    make_dataset("seer")
    dataset_db(url: directory_url, schema: SCHEMA, memory_limit: "1GiB")
    error = assert_raises(Sequelizer::DatasetSettingsConflictError) do
      Sequelizer.dataset_db(url: directory_url, schema: "seer", memory_limit: "2GiB")
    end

    assert_includes error.message, { "memory_limit" => "1GiB" }.inspect
    assert_includes error.message, { "memory_limit" => "2GiB" }.inspect
  end

  def test_max_connections_sets_the_pool_size
    make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA, max_connections: 7)

    assert_equal 7, db.pool.max_size
    error = assert_raises(Sequelizer::DatasetSettingsConflictError) do
      Sequelizer.dataset_db(url: directory_url, schema: SCHEMA, max_connections: 5)
    end
    assert_includes error.message, "max_connections"
  end

  def test_a_write_to_the_dataset_fails
    make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)

    insert = assert_raises(Sequel::DatabaseError) { db[patients].insert(id: 3, gender_concept_id: 8507) }
    delete = assert_raises(Sequel::DatabaseError) { db[patients].delete }

    assert_match(/"INSERT" on database "dataset_synpuf" which is attached in read-only mode/, insert.message)
    assert_match(/"DELETE" on database "dataset_synpuf" which is attached in read-only mode/, delete.message)
    assert_equal 2, db[patients].count
  end

  def test_a_table_name_without_a_schema_reads_the_dataset_only_in_with_dataset
    make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)

    assert_equal 2, Sequelizer.with_dataset(url: directory_url, schema: SCHEMA) { |d| d[:patients].count }
    error = assert_raises(Sequel::DatabaseError) { db[:patients].count }
    assert_match(/Table with name patients does not exist/, error.message)
  end

  def test_a_lazy_dataset_that_runs_after_with_dataset_fails
    make_dataset
    lazy = Sequelizer.with_dataset(url: directory_url, schema: SCHEMA) { |db| db[:patients] }

    assert_raises(Sequel::DatabaseError) { lazy.count }
  end

  def test_nested_with_dataset_restores_the_outer_search_path
    make_dataset
    make_dataset("seer", rows: 3)
    counts = Sequelizer.with_dataset(url: directory_url, schema: SCHEMA) do |db|
      inner = Sequelizer.with_dataset(url: directory_url, schema: "seer") { |d| d[:patients].count }
      [ inner, db[:patients].count ]
    end

    assert_equal [ 3, 2 ], counts
  end

  def test_with_dataset_restores_the_search_path_when_the_block_raises
    make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA, max_connections: 1)
    assert_raises(RuntimeError) { Sequelizer.with_dataset(url: directory_url, schema: SCHEMA, max_connections: 1) { raise "boom" } }

    assert_raises(Sequel::DatabaseError) { db[:patients].count }
  end

  def test_threads_in_with_dataset_at_once_read_their_own_datasets
    make_dataset
    make_dataset("seer", rows: 3)
    inside = Queue.new
    go = Queue.new
    read = lambda do |schema|
      Thread.new do
        Sequelizer.with_dataset(url: directory_url, schema:) do |db|
          inside << schema
          go.pop
          db[:patients].count
        end
      end
    end
    threads = [ read.call(SCHEMA), read.call("seer") ]
    2.times { inside.pop }
    2.times { go << :go }

    assert_equal [ 2, 3 ], threads.map(&:value)
  end

  def test_a_create_without_a_catalog_goes_to_the_in_memory_database_and_hides_the_dataset_table
    make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)
    Sequelizer.with_dataset(url: directory_url, schema: SCHEMA) do |d|
      d.create_table(:patients) { Integer :n }

      assert_equal 0, d[:patients].count
    end

    assert_equal 0, db[Sequel[:memory][:main][:patients]].count
    assert_equal 2, db[patients].count
  end

  def test_every_pool_connection_reads_the_attached_datasets
    make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)
    db.disconnect

    assert_equal 2, db[patients].count
  end

  def test_a_replaced_dataset_file_is_read_only_after_close_dataset_dbs
    file = make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)
    db[patients].count
    File.rename(build_dataset_file(@root.join("replacement.duckdb"), rows: 5), file)
    db.disconnect

    assert_equal 2, db[patients].count

    Sequelizer.close_dataset_dbs
    fresh = dataset_db(url: directory_url, schema: SCHEMA)

    refute_same db, fresh
    assert_equal 5, fresh[patients].count
  end

  def test_sequel_does_not_keep_a_reference_to_the_dataset_database
    make_dataset

    refute_includes Sequel::DATABASES, dataset_db(url: directory_url, schema: SCHEMA)
  end

  def test_a_failed_attach_closes_the_database_when_no_dataset_is_attached
    file = @root.join(SCHEMA, "gdm.duckdb")
    file.dirname.mkpath
    file.write("not a DuckDB file")
    databases = Sequel::DATABASES.size

    assert_raises(Sequel::DatabaseError) { Sequelizer.dataset_db(url: directory_url, schema: SCHEMA, threads: 1) }
    assert_equal databases, Sequel::DATABASES.size

    file.delete
    make_dataset

    # Other settings work, so the failed call left no database open.
    assert_equal 2, dataset_db(url: directory_url, schema: SCHEMA, threads: 2)[patients].count
  end

  def test_a_failed_attach_keeps_the_other_datasets
    make_dataset
    db = dataset_db(url: directory_url, schema: SCHEMA)
    broken = @root.join("broken", "gdm.duckdb")
    broken.dirname.mkpath
    broken.write("not a DuckDB file")

    assert_raises(Sequel::DatabaseError) { Sequelizer.dataset_db(url: directory_url, schema: "broken") }
    assert_same db, dataset_db(url: directory_url, schema: SCHEMA)
    assert_equal 2, db[patients].count
  end

  def test_the_url_scheme_can_be_in_any_case
    make_dataset

    assert_equal 2, dataset_db(url: "DuckDB://#{@root}", schema: SCHEMA)[patients].count
  end

  def test_readonly_false_raises
    error = assert_raises(ArgumentError) { Sequelizer.dataset_db(url: directory_url, schema: SCHEMA, readonly: false) }

    assert_match(/read-write .* not supported yet/, error.message)
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
    assert Sequelizer::DuckDBDataset.directory_url?("DUCKDB://#{@root}")
    refute Sequelizer::DuckDBDataset.directory_url?("duckdb://#{file}")
    refute Sequelizer::DuckDBDataset.directory_url?("postgres://localhost/gdm")
  end
end
