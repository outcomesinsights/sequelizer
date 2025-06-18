require_relative '../../../test_helper'
require 'sequel'
require 'sequel/extensions/sql_recorder'

class TestSqlRecorder < Minitest::Test

  def setup
    # Use mock database for these tests since we're not conflicting anymore
    @db = Sequel.mock
    @db.extension :sql_recorder
  end

  def test_extension_registration
    assert_respond_to @db, :sql_recorder
  end

  def test_sql_recorder_initialized_as_empty_array
    assert_instance_of Array, @db.sql_recorder
    assert_empty @db.sql_recorder
  end

  def test_records_select_statements
    @db[:users].all

    assert_operator(@db.sql_recorder.length, :>=, 1, 'Should record at least one SQL statement')
    assert(@db.sql_recorder.any? { |sql| sql.include?('SELECT * FROM users') || sql.include?('SELECT * FROM `users`') }, 'Should record the SELECT statement')
  end

  def test_records_insert_statements
    @db[:users].insert(name: 'John', email: 'john@example.com', age: 30)

    assert_operator(@db.sql_recorder.length, :>=, 1, 'Should record at least one SQL statement')
    assert(@db.sql_recorder.any? { |sql| sql.include?('INSERT INTO users') || sql.include?('INSERT INTO `users`') }, 'Should record INSERT statement')
    assert(@db.sql_recorder.any? { |sql| sql.include?('John') }, 'Should include the data')
  end

  def test_records_update_statements
    @db[:users].where(id: 1).update(name: 'Jane')

    assert_operator(@db.sql_recorder.length, :>=, 1, 'Should record at least one SQL statement')
    assert(@db.sql_recorder.any? { |sql| sql.include?('UPDATE users SET') || sql.include?('UPDATE `users` SET') }, 'Should record UPDATE statement')
    assert(@db.sql_recorder.any? { |sql| sql.include?('Jane') }, 'Should include the updated data')
  end

  def test_records_delete_statements
    @db[:users].where(id: 1).delete

    assert_operator(@db.sql_recorder.length, :>=, 1, 'Should record at least one SQL statement')
    assert(@db.sql_recorder.any? { |sql| sql.include?('DELETE FROM users') || sql.include?('DELETE FROM `users`') }, 'Should record DELETE statement')
  end

  def test_records_multiple_sql_statements
    initial_count = @db.sql_recorder.length

    @db[:users].all
    @db[:posts].where(id: 1).first
    @db[:comments].count

    assert_operator(@db.sql_recorder.length, :>=, initial_count + 3, 'Should record at least 3 more SQL statements')
    assert(@db.sql_recorder.any? { |sql| sql.include?('SELECT * FROM users') || sql.include?('SELECT * FROM `users`') }, 'Should record users query')
    assert(@db.sql_recorder.any? do |sql|
      sql.include?('SELECT * FROM posts WHERE (id = 1)')
    end, 'Should record posts query')
    assert(@db.sql_recorder.any? do |sql|
      sql.include?('SELECT count(*) AS count FROM comments')
    end, 'Should record count query')
  end

  def test_sql_recorder_accumulates_across_multiple_operations
    initial_count = @db.sql_recorder.length

    @db[:users].all
    count_after_first = @db.sql_recorder.length

    assert_operator(count_after_first, :>, initial_count, 'Should record first query')

    @db[:posts].first
    count_after_second = @db.sql_recorder.length

    assert_operator(count_after_second, :>, count_after_first, 'Should record second query')

    @db[:comments].insert(text: 'Hello')
    count_after_third = @db.sql_recorder.length

    assert_operator(count_after_third, :>, count_after_second, 'Should record third query')
  end

  def test_sql_recorder_persists_until_manually_cleared
    @db[:users].all
    @db[:posts].all

    assert_operator(@db.sql_recorder.length, :>=, 2, 'Should record multiple statements')

    # Manually clear (this is how consumers would reset the log)
    @db.sql_recorder.clear

    assert_empty @db.sql_recorder

    @db[:comments].all

    assert_operator(@db.sql_recorder.length, :>=, 1, 'Should record new statements after clear')
  end

  def test_handles_complex_queries_with_joins
    @db[:users].join(:posts, user_id: :id).where(Sequel[:users][:active] => true).all

    assert_operator(@db.sql_recorder.length, :>=, 1, 'Should record at least one SQL statement')
    recorded_sql = @db.sql_recorder.join(' ')

    assert_includes(recorded_sql, 'SELECT', 'Should contain SELECT')
    assert(recorded_sql.include?('FROM users') || recorded_sql.include?('FROM `users`'), 'Should contain FROM users')
    assert_includes(recorded_sql, 'JOIN', 'Should contain JOIN')
  end

  def test_handles_queries_with_parameters
    @db[:users].where(name: 'John', age: 25).all

    assert_operator(@db.sql_recorder.length, :>=, 1, 'Should record at least one SQL statement')
    recorded_sql = @db.sql_recorder.join(' ')

    assert_includes(recorded_sql, 'John', 'Should include name parameter')
    assert_includes(recorded_sql, '25', 'Should include age parameter')
  end

  def test_thread_safety_with_concurrent_queries
    threads = []

    10.times do |i|
      threads << Thread.new do
        @db[:table].where(id: i).first
      end
    end

    threads.each(&:join)

    # Should have recorded all 10 queries
    assert_operator(@db.sql_recorder.length, :>=, 10, 'Should record at least 10 queries')
    (0..9).each do |i|
      assert(@db.sql_recorder.any? { |sql| sql.include?("WHERE (id = #{i})") }, "Should record query for id #{i}")
    end
  end

  def test_module_extension_method_initializes_properly
    # Test the self.extended method directly
    fresh_db = Sequel.mock
    fresh_db.extend(Sequel::SqlRecorder)
    Sequel::SqlRecorder.extended(fresh_db)

    assert_respond_to fresh_db, :sql_recorder
    assert_instance_of Array, fresh_db.sql_recorder
    assert_instance_of Mutex, fresh_db.instance_variable_get(:@sql_recorder_mutex)
  end

  def test_sql_recorder_mutex_is_initialized
    assert_instance_of Mutex, @db.instance_variable_get(:@sql_recorder_mutex)
  end

  def test_extension_can_be_added_to_existing_database
    plain_db = Sequel.mock

    refute_respond_to plain_db, :sql_recorder

    plain_db.extension :sql_recorder

    assert_respond_to plain_db, :sql_recorder
    assert_instance_of Array, plain_db.sql_recorder
  end

  def test_sql_recorder_does_not_conflict_with_mock_sqls
    # Test that our sql_recorder doesn't interfere with mock's sqls
    mock_db = Sequel.mock
    mock_db.extension :sql_recorder

    # Both should work independently
    assert_respond_to mock_db, :sqls # Mock's built-in
    assert_respond_to mock_db, :sql_recorder # Our extension

    # Execute a query
    mock_db[:test].all

    # Both should record (though possibly differently)
    assert_instance_of Array, mock_db.sqls
    assert_instance_of Array, mock_db.sql_recorder
  end

  def test_database_extension_registration
    # Test that the extension is properly registered with Sequel
    # Check that we can load the extension without error
    fresh_db = Sequel.mock
    fresh_db.extension :sql_recorder

    assert_respond_to fresh_db, :sql_recorder
  end

  def test_attr_reader_sql_recorder_works
    # Directly test the attr_reader
    assert_same @db.instance_variable_get(:@sql_recorder), @db.sql_recorder
  end

  def test_log_connection_yield_method_exists
    assert_respond_to @db, :log_connection_yield
    assert_includes Sequel::SqlRecorder.instance_methods, :log_connection_yield
  end

  def test_manual_sql_recording_functionality
    # Test that we can manually record SQL using the method structure
    test_sql = 'SELECT * FROM manual_test'

    # Verify sql_recorder starts empty or with existing content
    initial_count = @db.sql_recorder.length

    # Manually add SQL using the same structure as log_connection_yield
    @db.instance_variable_get(:@sql_recorder_mutex).synchronize do
      @db.sql_recorder.push(test_sql)
    end

    assert_equal initial_count + 1, @db.sql_recorder.length
    assert_includes @db.sql_recorder, test_sql
  end

end
