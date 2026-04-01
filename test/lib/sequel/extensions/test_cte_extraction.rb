require_relative '../../../test_helper'
require 'sequel'
require 'sequel/extensions/platform'
require 'sequel/extensions/cte_extraction'

class TestCteExtractionExtractor < Minitest::Test

  # --- Extractor: recursive_extract_ctes ---

  def test_extracts_with_clauses
    db = Sequel.mock(host: :postgres)
    ds = db[:main].with(:cohort, db[:visits].where(type: 'inpatient'))

    extractor = Sequel::CteExtraction::Extractor.new
    cleaned = extractor.recursive_extract_ctes(ds)

    assert_equal 1, extractor.ctes.size
    assert_equal :cohort, extractor.ctes.first[0]
    assert_nil cleaned.opts[:with]
  end

  def test_preserves_no_temp_table_ctes
    db = Sequel.mock(host: :postgres)
    ds = db[:main]
         .with(:keep_me, db[:kept], no_temp_table: true)
         .with(:extract_me, db[:extracted])

    extractor = Sequel::CteExtraction::Extractor.new
    cleaned = extractor.recursive_extract_ctes(ds)

    assert_equal 1, extractor.ctes.size
    assert_equal :extract_me, extractor.ctes.first[0]
    assert_equal 1, cleaned.opts[:with].size
    assert_equal :keep_me, cleaned.opts[:with].first[:name]
  end

  def test_extracts_from_subqueries
    db = Sequel.mock(host: :postgres)
    subquery = db[:visits].where(type: 'inpatient')
    ds = db.from(Sequel.as(subquery, :v))

    extractor = Sequel::CteExtraction::Extractor.new
    cleaned = extractor.recursive_extract_ctes(ds)

    from_expr = cleaned.opts[:from].first

    assert_kind_of Sequel::SQL::AliasedExpression, from_expr
  end

  def test_extracts_join_subqueries
    db = Sequel.mock(host: :postgres)
    subquery = db[:visits].where(type: 'inpatient')
    ds = db[:patients].join(Sequel.as(subquery, :v), patient_id: :id)

    extractor = Sequel::CteExtraction::Extractor.new
    cleaned = extractor.recursive_extract_ctes(ds)

    assert cleaned.opts[:join]
  end

  def test_extracts_compound_datasets
    db = Sequel.mock(host: :postgres)
    ds1 = db[:visits].where(type: 'inpatient')
                     .with(:cohort, db[:cohorts].where(active: true))
    ds2 = db[:visits].where(type: 'outpatient')
    ds = ds1.union(ds2)

    extractor = Sequel::CteExtraction::Extractor.new
    extractor.recursive_extract_ctes(ds)

    assert_equal 1, extractor.ctes.size
    assert_equal :cohort, extractor.ctes.first[0]
  end

  def test_extracts_where_subqueries
    db = Sequel.mock(host: :postgres)
    subquery = db[:cohort].select(:patient_id)
                          .with(:cohort, db[:visits].where(type: 'inpatient'))
    ds = db[:patients].where(id: subquery)

    extractor = Sequel::CteExtraction::Extractor.new
    extractor.recursive_extract_ctes(ds)

    assert_equal 1, extractor.ctes.size
    assert_equal :cohort, extractor.ctes.first[0]
  end

  def test_returns_dataset_unchanged_when_no_ctes
    db = Sequel.mock(host: :postgres)
    ds = db[:patients].where(active: true)

    extractor = Sequel::CteExtraction::Extractor.new
    cleaned = extractor.recursive_extract_ctes(ds)

    assert_empty extractor.ctes
    assert_equal ds.sql, cleaned.sql
  end

  # --- Extractor: extract_cte_expr ---

  def test_extract_cte_expr_with_plain_dataset
    db = Sequel.mock(host: :postgres)
    ds = db[:visits].where(type: 'inpatient')

    extractor = Sequel::CteExtraction::Extractor.new
    result = extractor.extract_cte_expr(ds)

    assert_kind_of Sequel::Dataset, result
  end

  def test_extract_cte_expr_with_aliased_dataset
    db = Sequel.mock(host: :postgres)
    ds = db[:visits].where(type: 'inpatient')
    aliased = Sequel.as(ds, :v)

    extractor = Sequel::CteExtraction::Extractor.new
    result = extractor.extract_cte_expr(aliased)

    assert_kind_of Sequel::SQL::AliasedExpression, result
    assert_equal :v, result.alias
  end

  def test_extract_cte_expr_passes_through_non_datasets
    extractor = Sequel::CteExtraction::Extractor.new

    assert_equal :patients, extractor.extract_cte_expr(:patients)
    assert_equal 'literal', extractor.extract_cte_expr('literal')
  end

  # --- Extractor: sorted_ctes (topological sort) ---

  def test_sorts_ctes_in_dependency_order
    db = Sequel.mock(host: :postgres)

    cte_a = db[:visits].where(type: 'inpatient')
    cte_b = db[:a].where(active: true)

    ds = db[:main]
         .with(:b, cte_b)
         .with(:a, cte_a)

    extractor = Sequel::CteExtraction::Extractor.new
    extractor.recursive_extract_ctes(ds)
    sorted = extractor.sorted_ctes
    names = sorted.map(&:first)

    assert_equal 2, names.size
    assert_operator names.index(:a), :<, names.index(:b)
  end

  def test_deduplicates_ctes_by_name
    db = Sequel.mock(host: :postgres)

    ds = db[:main]
         .with(:cohort, db[:visits].where(type: 'inpatient'))
         .union(
           db[:other].with(:cohort, db[:visits].where(type: 'inpatient')),
         )

    extractor = Sequel::CteExtraction::Extractor.new
    extractor.recursive_extract_ctes(ds)
    names = extractor.sorted_ctes.map(&:first)

    assert_equal [:cohort], names
  end

  # --- AstExtractor ---

  def test_ast_extractor_transforms_dataset_in_expression
    db = Sequel.mock(host: :postgres)

    subquery = db[:cohort].select(:patient_id)
                          .with(:cohort, db[:visits].where(type: 'inpatient'))
    where_expr = Sequel::SQL::BooleanExpression.new(:IN, Sequel[:id], subquery)

    extractor = Sequel::CteExtraction::Extractor.new
    ast = Sequel::CteExtraction::AstExtractor.new(extractor)
    result = ast.transform(where_expr)

    assert_equal 1, extractor.ctes.size
    assert_equal :cohort, extractor.ctes.first[0]
    assert_kind_of Sequel::SQL::BooleanExpression, result
  end

  def test_ast_extractor_passes_through_non_datasets
    extractor = Sequel::CteExtraction::Extractor.new
    ast = Sequel::CteExtraction::AstExtractor.new(extractor)

    expr = Sequel.lit('1 = 1')
    result = ast.transform(expr)

    assert_empty extractor.ctes
    assert_equal expr, result
  end

  # --- Nested and Multi-level Extraction ---

  def test_extracts_nested_ctes_within_cte_definitions
    db = Sequel.mock(host: :postgres)

    # inner CTE is nested inside outer CTE's definition
    inner_ds = db[:raw_visits].where(active: true)
    outer_ds = db[:inner_cohort].select(:patient_id)
                                .with(:inner_cohort, inner_ds)

    ds = db[:main].with(:outer_cohort, outer_ds)

    extractor = Sequel::CteExtraction::Extractor.new
    extractor.recursive_extract_ctes(ds)

    names = extractor.ctes.map(&:first)

    assert_includes names, :inner_cohort
    assert_includes names, :outer_cohort
  end

  def test_extracts_multiple_interdependent_ctes
    db = Sequel.mock(host: :postgres)

    # c depends on b, b depends on a
    cte_a = db[:visits].where(type: 'inpatient')
    cte_b = db[:a].where(active: true)
    cte_c = db[:b].select(:patient_id)

    ds = db[:main]
         .with(:c, cte_c)
         .with(:b, cte_b)
         .with(:a, cte_a)

    extractor = Sequel::CteExtraction::Extractor.new
    extractor.recursive_extract_ctes(ds)
    sorted = extractor.sorted_ctes
    names = sorted.map(&:first)

    assert_equal 3, names.size
    assert_operator names.index(:a), :<, names.index(:b)
    assert_operator names.index(:b), :<, names.index(:c)
  end

  def test_strips_metadata_keys_from_extracted_cte_opts
    db = Sequel.mock(host: :postgres)

    ds = db[:main].with(:cohort, db[:visits], recursive: true)

    extractor = Sequel::CteExtraction::Extractor.new
    extractor.recursive_extract_ctes(ds)

    _name, _ds, opts = extractor.ctes.first

    # :name, :dataset, :no_temp_table should be stripped; :recursive kept
    refute opts.key?(:name)
    refute opts.key?(:dataset)
    refute opts.key?(:no_temp_table)
    assert opts[:recursive]
  end

  def test_cleaned_dataset_produces_valid_sql
    db = Sequel.mock(host: :postgres)

    ds = db[:main].with(:cohort, db[:visits].where(type: 'inpatient'))

    extractor = Sequel::CteExtraction::Extractor.new
    cleaned = extractor.recursive_extract_ctes(ds)

    # Should produce SQL without WITH clause
    sql = cleaned.sql

    refute_includes sql, 'WITH'
    assert_includes sql, '"main"'
  end

end

class TestCteExtractionIntegration < Minitest::Test

  def setup
    @original_config_dir = Sequel::Platform.config_dir
    Sequel::Platform.config_dir = File.expand_path('../../../../config/platforms', __dir__)
  end

  def teardown
    Sequel::Platform.config_dir = @original_config_dir
  end

  # --- Extension Registration ---

  def test_registers_extension
    db = Sequel.mock(host: :postgres)
    db.extension :cte_extraction

    assert_respond_to db[:t], :with_cte_extraction
  end

  # --- DatasetMethods: with_cte_extraction ---

  def test_returns_with_clauses_when_prefers_cte
    db = Sequel.mock(host: :postgres)
    db.extension :platform, :cte_extraction

    ds = db[:main].with(:cohort, db[:visits].where(type: 'inpatient'))
    result = ds.with_cte_extraction

    assert result.opts[:with]
    assert_equal 1, result.opts[:with].size
    assert_equal :cohort, result.opts[:with].first[:name]
  end

  def test_returns_unchanged_when_no_ctes
    db = Sequel.mock(host: :postgres)
    db.extension :platform, :cte_extraction

    ds = db[:patients].where(active: true)
    result = ds.with_cte_extraction

    assert_equal ds.sql, result.sql
  end

  def test_without_platform_defaults_to_cte_mode
    db = Sequel.mock(host: :postgres)
    db.extension :cte_extraction

    ds = db[:main].with(:cohort, db[:visits].where(type: 'inpatient'))
    result = ds.with_cte_extraction

    assert result.opts[:with]
    assert_equal :cohort, result.opts[:with].first[:name]
  end

  def test_preserves_with_opts
    db = Sequel.mock(host: :postgres)
    db.extension :platform, :cte_extraction

    ds = db[:main].with(:cohort, db[:visits], recursive: true)
    result = ds.with_cte_extraction

    with_entry = result.opts[:with].first

    assert_equal :cohort, with_entry[:name]
    assert with_entry[:recursive]
  end

  # --- TempTableExecutor ---

  def test_executor_adds_sql_statements_method
    db = Sequel.mock(host: :postgres)
    ctes = [[:cohort, db[:visits].where(type: 'inpatient'), {}]]

    executor = Sequel::CteExtraction::TempTableExecutor.new(db[:main], ctes, db)
    result = executor.to_dataset

    assert_respond_to result, :sql_statements
    stmts = result.sql_statements

    assert_kind_of Hash, stmts
    assert stmts.key?(:cohort)
    assert stmts.key?(:query)
  end

  def test_executor_adds_drop_temp_tables_method
    db = Sequel.mock(host: :postgres)
    ctes = [[:cohort, db[:visits], {}]]

    executor = Sequel::CteExtraction::TempTableExecutor.new(db[:main], ctes, db)
    result = executor.to_dataset

    assert_respond_to result, :drop_temp_tables
  end

  def test_executor_qualifies_with_interim_schema
    db = Sequel.mock(host: :postgres)
    ctes = [[:cohort, db[:visits], {}]]

    executor = Sequel::CteExtraction::TempTableExecutor.new(
      db[:main], ctes, db,
      interim_schema: :scratch, interim_prefix: 'cte_'
    )
    qualified = executor.send(:qualify_table_name, :cohort)

    assert_kind_of Sequel::SQL::QualifiedIdentifier, qualified
    assert_equal :scratch, qualified.table
    assert_equal :cte_cohort, qualified.column
  end

  def test_executor_uses_temp_true_without_interim_schema
    db = Sequel.mock(host: :postgres)
    ctes = [[:cohort, db[:visits], {}]]

    executor = Sequel::CteExtraction::TempTableExecutor.new(db[:main], ctes, db)
    opts = executor.send(:build_create_options, db[:visits])

    assert opts[:temp]
    assert opts[:as]
  end

  def test_executor_omits_temp_with_interim_schema
    db = Sequel.mock(host: :postgres)
    ctes = [[:cohort, db[:visits], {}]]

    executor = Sequel::CteExtraction::TempTableExecutor.new(
      db[:main], ctes, db, interim_schema: :scratch
    )
    opts = executor.send(:build_create_options, db[:visits])

    refute opts[:temp]
    assert opts[:as]
  end

  # --- Platform integration ---

  def test_spark_returns_temp_table_executor_dataset
    db = Sequel.mock(host: :spark)
    db.extension :platform, :cte_extraction

    ds = db[:main].with(:cohort, db[:visits].where(type: 'inpatient'))
    result = ds.with_cte_extraction

    assert_respond_to result, :sql_statements
    assert_respond_to result, :drop_temp_tables
  end

  def test_athena_uses_temp_table_executor
    db = Sequel.mock(host: :athena)
    db.extension :platform, :cte_extraction

    ctes = [[:cohort, db[:visits].where(type: 'inpatient'), {}]]
    executor = Sequel::CteExtraction::TempTableExecutor.new(
      db[:main], ctes, db,
      interim_schema: :scratch,
      drop_table_needs_unquoted: true
    )
    result = executor.to_dataset

    assert_respond_to result, :sql_statements
    assert_respond_to result, :drop_temp_tables
  end

  # --- Temp Table Lifecycle via Mock DB ---

  def test_executor_creates_temp_tables_on_iteration
    db = Sequel.mock(host: :postgres, fetch: [{ id: 1 }])
    ctes = [[:cohort, db[:visits].where(type: 'inpatient'), {}]]

    executor = Sequel::CteExtraction::TempTableExecutor.new(db[:main], ctes, db)
    result = executor.to_dataset

    result.each { |_row| nil } # trigger iteration

    sqls = db.sqls

    # Should have CREATE TEMPORARY TABLE and DROP TABLE
    assert sqls.any? { |s| s.include?('CREATE') && s.include?('TEMPORARY') },
           "Expected CREATE TEMPORARY TABLE in: #{sqls}"
    assert sqls.any? { |s| s.include?('DROP') },
           "Expected DROP TABLE in: #{sqls}"
  end

  def test_executor_drops_tables_in_reverse_order
    db = Sequel.mock(host: :postgres, fetch: [{ id: 1 }])
    ctes = [
      [:first_cte, db[:visits], {}],
      [:second_cte, db[:patients], {}],
    ]

    executor = Sequel::CteExtraction::TempTableExecutor.new(db[:main], ctes, db)
    result = executor.to_dataset

    result.each { |_row| nil }

    sqls = db.sqls
    drop_sql = sqls.select { |s| s.include?('DROP') }.join(' ')

    # Both tables should be dropped
    assert_includes drop_sql, 'second_cte'
    assert_includes drop_sql, 'first_cte'
    # second_cte should be dropped before first_cte (reverse dependency order)
    assert_operator drop_sql.index('second_cte'), :<, drop_sql.index('first_cte')
  end

  def test_executor_sql_statements_returns_all_cte_queries
    db = Sequel.mock(host: :postgres)
    cte_a = db[:visits].where(type: 'inpatient')
    cte_b = db[:patients].where(active: true)
    ctes = [[:cte_a, cte_a, {}], [:cte_b, cte_b, {}]]

    executor = Sequel::CteExtraction::TempTableExecutor.new(db[:main], ctes, db)
    result = executor.to_dataset
    stmts = result.sql_statements

    assert_equal 3, stmts.size
    assert stmts.key?(:cte_a)
    assert stmts.key?(:cte_b)
    assert stmts.key?(:query)
    assert_includes stmts[:cte_a], 'inpatient'
    assert_includes stmts[:cte_b], 'active'
  end

  # --- SQL Generation Verification ---

  def test_cte_reattach_generates_correct_sql
    db = Sequel.mock(host: :postgres)
    db.extension :platform, :cte_extraction

    ds = db[:main].with(:cohort, db[:visits].where(type: 'inpatient'))
    result = ds.with_cte_extraction
    sql = result.sql

    assert_includes sql, 'WITH'
    assert_includes sql, '"cohort"'
    assert_includes sql, 'inpatient'
  end

  def test_multiple_ctes_reattach_in_dependency_order
    db = Sequel.mock(host: :postgres)
    db.extension :platform, :cte_extraction

    cte_a = db[:visits].where(type: 'inpatient')
    cte_b = db[:a].select(:patient_id)

    ds = db[:main]
         .with(:b, cte_b)
         .with(:a, cte_a)
    result = ds.with_cte_extraction
    sql = result.sql

    # :a should appear before :b in the WITH clause
    assert_operator sql.index('"a"'), :<, sql.index('"b"')
  end

end
