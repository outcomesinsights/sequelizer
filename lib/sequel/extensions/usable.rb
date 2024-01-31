module Sequel
  module Usable
    def use(schema_name)
      run(use_sql(schema_name))
    end

    private

    def use_sql(schema_name)
      "USE #{quote_identifier(schema_name)}"
    end
  end

  Database.register_extension(:usable, Usable)
end
