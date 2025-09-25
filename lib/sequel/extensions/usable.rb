module Sequel

  # = Usable
  #
  # Sequel extension that provides a convenient +use+ method for switching
  # the current database/schema context. This is particularly useful for
  # databases that support the USE statement like MySQL, SQL Server, and
  # some big data engines.
  #
  # @example
  #   db.extension :usable
  #   db.use(:my_schema)
  #   # Executes: USE `my_schema`
  module Usable

    # Switches to the specified database or schema.
    #
    # Executes a USE statement to change the current database context.
    # The schema name is properly quoted using the database's identifier
    # quoting rules.
    #
    # @param schema_name [Symbol, String] the name of the schema/database to use
    # @example
    #   db.use(:production_db)
    #   db.use('test_schema')
    def use(schema_name)
      run(use_sql(schema_name))
    end

    private

    # Generates the USE SQL statement for the given schema name.
    #
    # @param schema_name [Symbol, String] the schema name to use
    # @return [String] the USE SQL statement
    def use_sql(schema_name)
      "USE #{literal(schema_name)}"
    end

  end

  Database.register_extension(:usable, Usable)

end
