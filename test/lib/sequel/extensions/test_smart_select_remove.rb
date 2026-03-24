require_relative '../../../test_helper'
require 'sequel'
require 'sequel/extensions/smart_select_remove'

class TestSmartSelectRemove < Minitest::Test

  def setup
    @db = Sequel.mock
    @db.extension :smart_select_remove
  end

  # --- Static resolution via from_self ---

  def test_resolves_columns_from_from_self_chain
    ds = @db[:items].select(:a, :b, :c).from_self
    result = ds.select_remove(:c)

    assert_equal %i[a b], result.opts[:select]
    assert_empty @db.sqls, 'should not execute SQL'
  end

  def test_resolves_columns_from_nested_from_self
    ds = @db[:items].select(:a, :b, :c).from_self.from_self
    result = ds.select_remove(:b)

    assert_equal %i[a c], result.opts[:select]
    assert_empty @db.sqls, 'should not execute SQL'
  end

  def test_resolves_aliased_expressions
    ds = @db[:items].select(Sequel[:x].as(:a), Sequel[:y].as(:b)).from_self
    result = ds.select_remove(:b)

    assert_equal [:a], result.opts[:select]
    assert_empty @db.sqls, 'should not execute SQL'
  end

  def test_resolves_qualified_identifiers
    ds = @db[:items].select(Sequel[:t][:a], Sequel[:t][:b], Sequel[:t][:c]).from_self
    result = ds.select_remove(:b)

    assert_equal %i[a c], result.opts[:select]
    assert_empty @db.sqls, 'should not execute SQL'
  end

  def test_resolves_sequel_identifiers
    ds = @db[:items].select(Sequel.identifier(:a), Sequel.identifier(:b)).from_self
    result = ds.select_remove(:a)

    assert_equal [:b], result.opts[:select]
    assert_empty @db.sqls, 'should not execute SQL'
  end

  def test_removes_multiple_columns
    ds = @db[:items].select(:a, :b, :c, :d).from_self
    result = ds.select_remove(:b, :d)

    assert_equal %i[a c], result.opts[:select]
    assert_empty @db.sqls, 'should not execute SQL'
  end

  def test_resolves_aliased_from_self
    ds = @db[:items].select(:a, :b).from_self(alias: :t1)
    result = ds.select_remove(:a)

    assert_equal [:b], result.opts[:select]
    assert_empty @db.sqls, 'should not execute SQL'
  end

  def test_mixed_expression_types
    ds = @db[:items].select(:a, Sequel[:t][:b], Sequel[:x].as(:c)).from_self
    result = ds.select_remove(:b)

    assert_equal %i[a c], result.opts[:select]
    assert_empty @db.sqls, 'should not execute SQL'
  end

  # --- Fallback to original select_remove ---

  def test_falls_back_for_bare_dataset
    ds = @db[:items]
    ds.select_remove(:a)

    refute_empty @db.sqls, 'should execute SQL via columns!'
  end

  def test_falls_back_when_explicit_select_on_outer
    ds = @db[:items].select(:a, :b, :c)
    ds.select_remove(:c)

    refute_empty @db.sqls, 'should delegate to original select_remove'
  end

  def test_falls_back_for_unresolvable_expression
    ds = @db[:items].select(:a, Sequel.lit('1 as flag')).from_self
    ds.select_remove(:a)

    refute_empty @db.sqls, 'should fall back when a column cannot be resolved'
  end

  # --- select_remove extension is auto-loaded ---

  def test_select_remove_is_available
    db = Sequel.mock
    db.extension :smart_select_remove
    ds = db[:items].select(:a, :b)

    assert_respond_to ds, :select_remove
  end

  # --- Removing a column that does not exist is harmless ---

  def test_removing_nonexistent_column_is_noop
    ds = @db[:items].select(:a, :b).from_self
    result = ds.select_remove(:z)

    assert_equal %i[a b], result.opts[:select]
    assert_empty @db.sqls, 'should not execute SQL'
  end

end
