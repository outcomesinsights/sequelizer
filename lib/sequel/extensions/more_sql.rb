# frozen_string_literal: true

module Sequel

  # Provides additional SQL helper methods for database operations.
  #
  # The more_sql extension adds convenience methods for SQL operations that
  # aren't covered by Sequel's core functionality, particularly schema-related
  # operations like CREATE SCHEMA.
  #
  # @example Load the extension
  #   DB.extension :more_sql
  #
  # @example Create a schema
  #   DB.create_schema(:analytics)
  #   # Executes: CREATE SCHEMA "analytics"
  #
  # @example Create schema if it doesn't exist
  #   DB.create_schema(:staging, if_not_exists: true)
  #   # Executes: CREATE SCHEMA IF NOT EXISTS "staging"
  module MoreSql

    # Creates a database schema.
    #
    # Generates and executes a CREATE SCHEMA statement with optional
    # IF NOT EXISTS clause for idempotent schema creation.
    #
    # @param schema_name [Symbol, String] The name of the schema to create
    # @param opts [Hash] Options for schema creation
    # @option opts [Boolean] :if_not_exists (false) Only create the schema if it doesn't already exist
    #
    # @return [nil]
    #
    # @example Basic schema creation
    #   DB.create_schema(:reports)
    #   # Executes: CREATE SCHEMA "reports"
    #
    # @example Idempotent schema creation
    #   DB.create_schema(:analytics, if_not_exists: true)
    #   # Executes: CREATE SCHEMA IF NOT EXISTS "analytics"
    #
    # @example With string schema name
    #   DB.create_schema('user_data')
    #   # Executes: CREATE SCHEMA "user_data"
    def create_schema(schema_name, opts = {})
      run(create_schema_sql(schema_name, opts))
    end

    private

    # Generates the SQL for creating a schema.
    #
    # Builds a CREATE SCHEMA statement with proper identifier quoting
    # and optional IF NOT EXISTS clause.
    #
    # @param schema_name [Symbol, String] The name of the schema to create
    # @param opts [Hash] Options for schema creation
    # @option opts [Boolean] :if_not_exists (false) Include IF NOT EXISTS clause
    #
    # @return [String] The CREATE SCHEMA SQL statement
    #
    # @example
    #   create_schema_sql(:test, if_not_exists: true)
    #   # => 'CREATE SCHEMA IF NOT EXISTS "test"'
    def create_schema_sql(schema_name, opts)
      sql = 'CREATE SCHEMA '
      sql += 'IF NOT EXISTS ' if opts[:if_not_exists]
      sql += literal(schema_name)
      sql
    end

  end

  Database.register_extension(:more_sql, MoreSql)

end
