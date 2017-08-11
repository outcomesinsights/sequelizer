module Sequel
  module DbOpts
    class DbOptions
      attr :db
      def initialize(db)
        db.extension :settable
        @db = db
      end

      def to_hash
        @_to_hash ||= extract_db_opts
      end

      def extract_db_opts
        opt_regexp = /^#{db.database_type}_db_opt_/i

        Hash[db.opts.select { |k, _| k.to_s.match(opt_regexp) }.map { |k, v| [k.to_s.gsub(opt_regexp, '').to_sym, prep_value(k, v)] }]
      end

      def apply(c)
        sql_statements.each do |stmt|
          if db.respond_to?(:log_connection_execute)
            db.send(:log_connection_execute, c, stmt)
          elsif c.respond_to?(:log_connection_execute)
            c.send(:log_connection_execute, stmt)
          elsif c.respond_to?(:execute)
            cursor = c.send(:execute, stmt)
            if cursor && cursor.respond_to?(:close)
              cursor.close
            end
          elsif db.respond_to?(:execute)
            db.send(:execute, stmt)
          else
            raise "Failed to run SET queries"
          end
        end
      end

      def prep_value(k, v)
        v =~ /\W/ ? db.literal("#{v}") : v
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
