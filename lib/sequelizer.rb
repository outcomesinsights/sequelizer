require_relative 'sequelizer/version'
require_relative 'sequelizer/connection_maker'
require_relative 'sequelizer/monkey_patches/database_in_after_connect'
require_relative 'sequel/extensions/db_opts'
require_relative 'sequel/extensions/settable'

# = Sequelizer
#
# Sequelizer is a Ruby gem that simplifies database connections using Sequel.
# It allows users to configure database connections via config/database.yml
# or .env files, providing an easy-to-use interface for establishing database
# connections without hardcoding sensitive information.
#
# == Usage
#
# Include this module in any class where you'd like to quickly establish
# a Sequel connection to a database:
#
#   class MyClass
#     include Sequelizer
#
#     def some_method
#       db[:users].all  # Uses cached connection
#     end
#   end
#
# == Configuration Sources
#
# Configuration is loaded from multiple sources in order of precedence:
# 1. Passed options
# 2. .env file
# 3. Environment variables
# 4. config/database.yml
# 5. ~/.config/sequelizer/database.yml
#
# == Examples
#
#   # Use cached connection
#   db[:users].all
#
#   # Create new connection with custom options
#   new_db(adapter: 'postgres', host: 'localhost')
#
module Sequelizer

  # Returns the default options hash for database connections.
  #
  # @return [Hash] the default connection options
  def self.options
    Options.new.to_hash
  end

  # Instantiates and memoizes a database connection. The +db+ method instantiates
  # the connection on the first call and then memoizes itself so only a single
  # connection is used on repeated calls.
  #
  # @param options [Hash] an optional set of database connection options.
  #   If no options are provided, options are read from config/sequelizer.yml
  #   or from .env or from environment variables.
  # @return [Sequel::Database] the memoized database connection
  #
  # @example
  #   db[:users].all  # Uses cached connection
  #   db(adapter: 'postgres')[:products].count
  def db(options = {})
    @_sequelizer_db ||= new_db(options)
  end

  # Instantiates and returns a new database connection on each call.
  #
  # @param options [Hash] an optional set of database connection options.
  #   If no options are provided, options are read from config/sequelizer.yml
  #   or from .env or from environment variables.
  # @return [Sequel::Database] a new database connection
  #
  # @example
  #   conn1 = new_db
  #   conn2 = new_db  # Different connection instance
  #   new_db(force_new: true)  # Bypasses cache entirely
  def new_db(options = {})
    cached = find_cached(options)
    return cached if cached && !options[:force_new]

    @_sequelizer_cache[options] = ConnectionMaker.new(options).connection
  end

  # Finds a cached connection for the given options.
  #
  # @param options [Hash] the connection options to look up
  # @return [Sequel::Database, nil] the cached connection or nil if not found
  def find_cached(options)
    @_sequelizer_cache ||= {}
    @_sequelizer_cache[options]
  end

end
