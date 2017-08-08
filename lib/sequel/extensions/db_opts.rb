module Sequel
  module DbOpts
    class DbOptions
      attr :conn
      def initialize(conn)
        conn.extension :settable
        @conn = conn
      end

      def to_hash
        @_to_hash ||= extract_db_opts
      end

      def extract_db_opts
        opt_regexp = /^#{conn.database_type}_db_opt_/i

        Hash[conn.opts.select { |k, _| k.to_s.match(opt_regexp) }.map { |k, v| [k.to_s.gsub(opt_regexp, '').to_sym, prep_value(k, v)] }]
      end

      def apply(c)
        sql_statements.each do |stmt|
          c.execute(stmt)
        end
      end

      def prep_value(k, v)
        v =~ /\W/ ? conn.literal("#{v}") : v
      end

      def sql_statements
        conn.send(:set_sql, to_hash)
      end
    end

    def db_opts
      @db_opts ||= DbOptions.new(self)
    end
  end

  Database.register_extension(:db_opts, DbOpts)
end
