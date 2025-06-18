# frozen_string_literal: true

# == Overview
# 
# The sql_recorder extension records each SQL statement sent to the database
# in a thread-safe array accessible via the +sql_recorder+ method.
#
# == Usage
#
#   DB.extension :sql_recorder
#   DB[:users].all
#   DB[:posts].where(id: 1).first
#   
#   # Access recorded SQL statements
#   DB.sql_recorder 
#   # => ["SELECT * FROM users", "SELECT * FROM posts WHERE (id = 1) LIMIT 1"]
#   
#   # Clear the recorded statements
#   DB.sql_recorder.clear
#
# == Thread Safety
#
# The extension is thread-safe and uses a mutex to synchronize access to the
# SQL recording array when multiple threads are executing queries simultaneously.
#
# == Compatibility
#
# This extension is designed to work alongside mock databases and other SQL
# recording mechanisms. It uses the method name +sql_recorder+ to avoid
# conflicts with existing +sqls+ methods that may be present in test frameworks.
#
# Related module: Sequel::SqlRecorder

module Sequel

  # Extension module that adds SQL recording capabilities to Sequel databases.
  # When included, it provides a +sql_recorder+ method that returns an array
  # of all SQL statements executed against the database.
  module SqlRecorder

    # Returns the array of recorded SQL statements.
    # 
    # The array accumulates all SQL statements sent to the database since the
    # extension was loaded or since the last time +clear+ was called on the array.
    #
    # @return [Array<String>] array of SQL statement strings
    # @example
    #   DB.extension :sql_recorder
    #   DB[:users].all
    #   DB.sql_recorder #=> ["SELECT * FROM users"]
    attr_reader :sql_recorder

    # Intercepts SQL execution to record statements.
    # 
    # This method overrides Sequel's +log_connection_yield+ to capture each SQL
    # statement in a thread-safe manner before delegating to the parent implementation.
    #
    # @param sql [String] the SQL statement being executed
    # @param conn [Object] the database connection object
    # @param args [Object] additional arguments (optional)
    # @return [Object] result from the parent +log_connection_yield+ method
    def log_connection_yield(sql, conn, args = nil)
      @sql_recorder_mutex.synchronize { sql_recorder.push(sql) }
      super
    end

    # Initializes the SQL recording infrastructure when the extension is loaded.
    #
    # Sets up the mutex for thread-safe access and initializes the SQL recording
    # array. This method is automatically called when the extension is loaded
    # via +DB.extension :sql_recorder+.
    #
    # @param db [Sequel::Database] the database instance being extended
    def self.extended(db)
      db.instance_exec do
        @sql_recorder_mutex ||= Mutex.new
        @sql_recorder ||= []
      end
    end

  end

  Database.register_extension(:sql_recorder, SqlRecorder)

end