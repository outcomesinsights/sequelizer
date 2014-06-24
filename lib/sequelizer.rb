require 'sequelizer/version'
require 'sequelizer/connection_maker'

# Include this module in any class where you'd like to quickly establish
# a Sequel connection to a database.
module Sequelizer
  # Instantiates and memoizes a database connection.  The +db+ method instantiates
  # the connection on the first call and then memoizes itself so only a single
  # connection is used on repeated calls
  #
  # options :: an optional set of database connection options.
  #            If no options are provided, options are read from
  #            config/database.yml or from .env or from environment variables.
  def db(options = nil)
    @_sequelizer_db ||= new_db(options)
  end

  # Instantiates and returns a new database connection on each call.
  #
  # options :: an optional set of database connection options.
  #            If no options are provided, options are read from
  #            config/database.yml or from .env or from environment variables.
  def new_db(options = nil)
    cm = ConnectionMaker.new(options)
    conn = cm.connection
    conn.define_singleton_method(:sequelizer_options) do
      cm.options
    end
    conn
  end
end
