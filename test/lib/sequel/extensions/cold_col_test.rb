# frozen_string_literal: true

require_relative '../../../test_helper'
require_relative '../../../../lib/sequel/extensions/cold_col'

describe Sequel::ColdColDatabase do
  let(:db) do
    @db = Sequel.mock.extension(:cold_col)
    @db.cold_col_registry.set_schemas({
                                Sequel.lit('tab1') => [[:col1]],
                                Sequel.lit('tab2') => [[:col2]],
                                Sequel.lit('tab3') => [[:col3], [:col4]],
                                Sequel.lit('q.tab4') => [[:col5]]
                              })
    @db.extend_datasets do
      def supports_cte?
        true
      end
    end
    
    # Add with method to mock database to support CTEs
    def @db.with(*args)
      dataset.with(*args)
    end
    
    @db
  end

  def expect_columns(ds, *cols)
    _(ds.columns).must_equal(cols)
  end

  it 'should know columns from select * FROM tab' do
    expect_columns(db[:tab1], :col1)
  end

  it 'should know columns after append' do
    expect_columns(db[:tab1].select_append(Sequel.function(:min, :col1).as(:mini)), :col1, :mini)
  end

  it 'should know columns after select_all' do
    expect_columns(db[:tab1].select_all, :col1)
  end

  it 'should know columns after select_all(:tab1)' do
    expect_columns(db[:tab1].select_all(:tab1), :col1)
  end

  it 'should know columns after from_self' do
    expect_columns(db[:tab1].from_self, :col1)
  end

  it 'should know columns after a CTE' do
    ds = db[:cte1]
         .with(:cte1, db[:tab1])
    expect_columns(ds, :col1)
  end

  it 'should know columns after a JOIN' do
    ds = db[:tab1]
         .join(:tab2)
    expect_columns(ds, :col1, :col2)
  end

  it 'should know columns after a different kind of JOIN' do
    ds = db[:tab1]
         .join(db[:tab2])
    expect_columns(ds, :col1, :col2)
  end

  it 'should know columns from a JOIN and CTE' do
    ds = db[:tab1]
         .with(:cte1, db[:tab2])
         .join(db[:cte1])
    expect_columns(ds, :col1, :col2)
  end

  it 'should know columns from a select_all JOIN' do
    ds = db[:tab1]
         .join(db[:tab2], { Sequel[:tab1][:col1] => Sequel[:tab2][:col3] })
         .select_all(:tab1)
    expect_columns(ds, :col1)
  end

  it 'should know columns from an aliased select_all JOIN' do
    ds = db[:tab1].from_self(alias: :l)
                  .join(db[:tab2], { col3: :col1 })
                  .select_all(:l)
    expect_columns(ds, :col1)
  end

  it 'should know columns from an aliased select_all and added rhs column JOIN' do
    ds = db[:tab1].from_self(alias: :l)
                  .join(db[:tab2], { col3: :col1 }, table_alias: :r)
                  .select_all(:l)
                  .select_append(Sequel[:r][:col4])
    expect_columns(ds, :col1, :col4)
  end

  it 'should know columns from an aliased select_all rhs JOIN' do
    ds = db[:tab1].from_self(alias: :l)
                  .join(db[:tab2], { col3: :col1 }, table_alias: :r)
                  .select_all(:r)
    expect_columns(ds, :col2)
  end

  it 'should know columns from a directly aliased select_all rhs JOIN' do
    ds = db[:tab1].from_self(alias: :l)
                  .join(:tab2, { col3: :col1 }, table_alias: :r)
                  .select_all(:r)
    expect_columns(ds, :col2)
  end

  it 'should know columns from a a qualified JOIN' do
    ds = db[:tab1].from_self(alias: :l)
                  .join(Sequel[:q][:tab4], { col3: :col1 }, table_alias: :r)
                  .select_all(:r)
    expect_columns(ds, :col5)
  end
  it 'should remember columns from ctas' do
    db.create_table(:ctas_table, as: db.select(Sequel[1].as(:a)))
    ds = db[:ctas_table]
    expect_columns(ds, :a)
  end

  it 'should remember columns from create table' do
    db.create_table(:ddl_table) do
      String :a
    end
    ds = db[:ddl_table]
    expect_columns(ds, :a)
  end

  it 'should remember columns from view' do
    db.create_view(:ctas_view, db.select(Sequel[1].as(:a)))
    ds = db[:ctas_view]
    expect_columns(ds, :a)
  end

  it 'should ignore columns when asked, thus avoiding an issue with string-only SQL' do
    assert_raises { db.create_view(:ctas_view, 'SELECT 1 AS A') }
    db.create_view(:ctas_view, 'SELECT 1 AS A', dont_record: true)
  end

  it 'should handle load_schema with empty file' do
    require 'tempfile'
    require 'yaml'
    
    Tempfile.create(['schema', '.yml']) do |f|
      f.write({}.to_yaml)
      f.flush
      
      db.load_schema(f.path)
      # Should not raise error and schemas should remain unchanged
      expect_columns(db[:tab1], :col1)
    end
  end

  it 'should handle add_table_schema with symbol and string table names' do
    db.add_table_schema(:new_table, [[:col_a, {}], [:col_b, {}]])
    db.add_table_schema('string_table', [[:col_c, {}]])
    
    expect_columns(db[:new_table], :col_a, :col_b)
    expect_columns(db[:string_table], :col_c)
  end

  it 'should handle complex nested CTEs' do
    ds = db.with(:cte1, db[:tab1])
           .with(:cte2, db[:cte1].select(:col1))
           .from(:cte2)
    expect_columns(ds, :col1)
  end

  it 'should handle qualified table names in schema' do
    expect_columns(db[Sequel[:q][:tab4]], :col5)
  end

  it 'should handle aliased expressions in select' do
    ds = db[:tab1].select(Sequel[:col1].as(:renamed_col))
    expect_columns(ds, :renamed_col)
  end

  it 'should handle function calls with aliases' do
    ds = db[:tab1].select(Sequel.function(:count, :col1).as(:count_col1))
    expect_columns(ds, :count_col1)
  end

  it 'should handle multiple table joins with mixed syntax' do
    ds = db[:tab1]
         .join(:tab2, { col2: :col1 })
         .join(db[:tab3].as(:t3), { col3: :col1 })
    expect_columns(ds, :col1, :col2, :col3, :col4)
  end

  it 'should handle recursive schema merging with load_schema' do
    require 'tempfile'
    require 'yaml'
    
    # First schema file
    Tempfile.create(['schema1', '.yml']) do |f1|
      f1.write({ 'initial_table' => { columns: { 'col_x' => {} } } }.to_yaml)
      f1.flush
      db.load_schema(f1.path)
      
      # Second schema file  
      Tempfile.create(['schema2', '.yml']) do |f2|
        f2.write({ 'second_table' => { columns: { 'col_y' => {} } } }.to_yaml)
        f2.flush
        db.load_schema(f2.path)
        
        # Both schemas should be available
        expect_columns(db[:initial_table], :col_x)
        expect_columns(db[:second_table], :col_y)
      end
    end
  end

  # Additional tests to ensure refactoring preserves behavior
  describe 'Internal schema lookup behavior' do
    it 'should prioritize created tables over schemas' do
      db.add_table_schema(:priority_test, [[:schema_col, {}]])
      db.create_table(:priority_test) do
        String :created_col
      end
      expect_columns(db[:priority_test], :created_col)
    end

    it 'should handle deeply nested WITH clauses' do
      ds = db[:cte1]
           .with(:cte1, db[:tab1])
           .with(:cte2, db[:cte1])
           .with(:cte3, db[:cte2])
           .from(:cte3)
      expect_columns(ds, :col1)
    end

    it 'should handle mixed aliased and non-aliased sources' do
      ds = db[:tab1].from_self(alias: :t1)
                    .join(:tab2, { col2: :col1 })
                    .join(db[:tab3].as(:t3), { col3: :col1 })
                    .select_all(:t1)
                    .select_append(Sequel[:t3][:col4])
      expect_columns(ds, :col1, :col4)
    end

    it 'should handle column lookup with empty select lists' do
      ds = db.from(db[:tab1].where(id: 1))
      expect_columns(ds, :col1)
    end
  end
end
