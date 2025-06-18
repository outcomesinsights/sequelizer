module Sequel

  module DbOpts

    class DbOptions

      attr_reader :db

      def initialize(db)
        db.extension :settable
        @db = db
      end

      def to_hash
        @_to_hash ||= extract_db_opts
      end

      def extract_db_opts
        opt_regexp = /^#{db.database_type}_db_opt_/i

        db.opts.select do |k, _|
          k.to_s.match(opt_regexp)
        end.to_h { |k, v| [k.to_s.gsub(opt_regexp, '').to_sym, prep_value(k, v)] }
      end

      def apply(c)
        sql_statements.each do |stmt|
          db.send(:log_connection_execute, c, stmt)
        end
      end

      def prep_value(_k, v)
        v =~ /\W/ ? db.literal(v.to_s) : v
      end

      def sql_statements
        db.send(:set_sql, to_hash)
      end

    end

    def db_opts
      @db_opts ||= DbOptions.new(self)
    end

  end

  Database.register_extension(:db_opts, DbOpts)

end
