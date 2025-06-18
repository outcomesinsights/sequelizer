# frozen_string_literal: true

#
# The settable extension adds a convenient +set+ method to database connections
# for executing SET statements with key-value pairs. This is particularly useful
# for configuring database session parameters.
#
#   DB.extension :settable
#   DB.set(search_path: 'public', timezone: 'UTC')
#   # Executes: SET search_path=public
#   #           SET timezone=UTC
#
#   DB.set(work_mem: '256MB')
#   # Executes: SET work_mem=256MB
#
# The extension works with any database adapter and supports various value types
# including strings, numbers, booleans, and nil values.
#
# Related module: Sequel::Settable

module Sequel

  # The Settable module provides database configuration functionality through
  # SET statements. When loaded as an extension, it adds the +set+ method to
  # database connections.
  module Settable

    # Execute SET statements for the given options hash.
    #
    # Each key-value pair in the options hash is converted to a SET statement
    # and executed against the database. Multiple options result in multiple
    # SET statements being executed in sequence.
    #
    # @param opts [Hash] Hash of configuration options to set
    # @option opts [Object] key The configuration parameter name
    # @option opts [Object] value The value to set for the parameter
    #
    # @example Set a single parameter
    #   DB.set(timezone: 'UTC')
    #   # Executes: SET timezone=UTC
    #
    # @example Set multiple parameters
    #   DB.set(search_path: 'public', work_mem: '256MB')
    #   # Executes: SET search_path=public
    #   #           SET work_mem=256MB
    #
    # @example Different value types
    #   DB.set(port: 5432, autocommit: true, custom_setting: nil)
    #   # Executes: SET port=5432
    #   #           SET autocommit=true
    #   #           SET custom_setting=
    #
    # @return [void]
    def set(opts = {})
      set_sql(opts).each do |sql|
        run(sql)
      end
    end

    private

    # Generate SET SQL statements from options hash.
    #
    # Converts each key-value pair in the options hash into a SET SQL statement
    # string. This is a private helper method used internally by the +set+ method.
    #
    # @param opts [Hash] Hash of options to convert to SET statements
    # @return [Array<String>] Array of SET SQL statement strings
    #
    # @example
    #   set_sql(timezone: 'UTC', port: 5432)
    #   # => ["SET timezone=UTC", "SET port=5432"]
    def set_sql(opts)
      opts.map { |k, v| "SET #{k}=#{v}" }
    end

  end

  Database.register_extension(:settable, Settable)

end
