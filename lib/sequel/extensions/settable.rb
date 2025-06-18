module Sequel

  module Settable

    def set(opts = {})
      set_sql(opts).each do |sql|
        run(sql)
      end
    end

    private

    def set_sql(opts)
      opts.map { |k, v| "SET #{k}=#{v}" }
    end

  end

  Database.register_extension(:settable, Settable)

end
