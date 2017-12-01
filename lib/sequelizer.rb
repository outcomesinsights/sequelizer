require_relative 'sequelizer/version'
require_relative 'sequelizer/connection_maker'
require_relative 'sequelizer/monkey_patches/database_in_after_connect'
require_relative 'sequel/extensions/db_opts'
require_relative 'sequel/extensions/settable'

# Include this module in any class where you'd like to quickly establish
# a Sequel connection to a database.
module Sequelizer
  def self.options
    Options.new.to_hash
  end

  # Instantiates and memoizes a database connection.  The +db+ method instantiates
  # the connection on the first call and then memoizes itself so only a single
  # connection is used on repeated calls
  #
  # options :: an optional set of database connection options.
  #            If no options are provided, options are read from
  #            config/sequelizer.yml or from .env or from environment variables.
  def db(options = {})
    @_sequelizer_db ||= new_db(options)
  end

  # Instantiates and returns a new database connection on each call.
  #
  # options :: an optional set of database connection options.
  #            If no options are provided, options are read from
  #            config/sequelizer.yml or from .env or from environment variables.
  def new_db(options = {})
    cached = find_cached(options)
    return cached if cached && !options[:force_new]
    @cache[options] = ConnectionMaker.new(options).connection
  end

  def find_cached(options)
    @cache ||= {}
    @cache[options]
  end
end
