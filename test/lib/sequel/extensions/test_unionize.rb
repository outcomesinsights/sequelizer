require_relative '../../../test_helper'
require 'sequel'

class TestUnionize < Minitest::Test

  def test_should_unionize_a_single_dataset
    db = Sequel.mock(host: :spark).extension(:unionize)
    ds = db.unionize([db[:a]])

    # No SQL should be executed
    assert_empty(db.sqls)
    # The SQL should be a single select
    assert_equal('SELECT * FROM `a`', ds.sql)
  end

  def test_should_unionize_two_datasets
    db = Sequel.mock(host: :spark).extension(:unionize)
    ds = db.unionize([db[:a], db[:b]])

    # No SQL should be executed
    assert_empty(db.sqls)
    # The SQL should be a single select
    assert_equal('SELECT * FROM (SELECT * FROM `a` UNION SELECT * FROM `b`) AS `t1`', ds.sql)
  end

  def test_should_unionize_two_datasets_and_allow_all_option
    db = Sequel.mock(host: :spark).extension(:unionize)
    ds = db.unionize([db[:a], db[:b]], all: true)

    # No SQL should be executed
    assert_empty(db.sqls)
    # The SQL should be a single select
    assert_equal('SELECT * FROM (SELECT * FROM `a` UNION ALL SELECT * FROM `b`) AS `t1`', ds.sql)
  end

  def test_should_unionize_two_datasets_and_allow_from_self_option
    db = Sequel.mock(host: :spark).extension(:unionize)
    ds = db.unionize([db[:a], db[:b]], from_self: false)

    # No SQL should be executed
    assert_empty(db.sqls)
    # The SQL should be a single select
    assert_equal('SELECT * FROM `a` UNION SELECT * FROM `b`', ds.sql)
  end

  def test_should_unionize_four_datasets_as_sets_of_two
    db = Sequel.mock(host: :spark).extension(:unionize)
    ds = db.unionize([db[:a], db[:b], db[:c], db[:d]], chunk_size: 2, from_self: false)

    # Two things should be created
    assert_equal(
      [
        'CREATE TEMPORARY VIEW `temp_union_ac554bd85a4a6087511d4949f3a3c5a59c110cde` AS SELECT * FROM `a` UNION SELECT * FROM `b`',
        'CREATE TEMPORARY VIEW `temp_union_1e7e77a914d0b30cd33511f372c48d537ad81084` AS SELECT * FROM `c` UNION SELECT * FROM `d`',
      ], db.sqls
    )
    # The SQL should be a single select
    assert_equal(
      'SELECT * FROM `temp_union_ac554bd85a4a6087511d4949f3a3c5a59c110cde` UNION SELECT * FROM `temp_union_1e7e77a914d0b30cd33511f372c48d537ad81084`', ds.sql
    )
  end

  def test_should_unionize_8_datasets_as_sets_of_two_then_another_two
    db = Sequel.mock(host: :spark).extension(:unionize)
    dses = %i[a b c d e f g h].map { |letter| db[letter] }
    ds = db.unionize(dses, chunk_size: 2, from_self: false)

    # Two things should be created
    assert_equal(6, db.sqls.length)
    # The SQL should be a single select
    assert_equal(
      'SELECT * FROM `temp_union_07a3e9f8f94e096301b62afd61b4315110ec0c3d` UNION SELECT * FROM `temp_union_ff3e49e7501c97ee5e69f112cc42bb7121f379f1`', ds.sql
    )
  end

end
