# frozen_string_literal: true

#
# The sqls extension will record each SQL statement sent to the
# database
#
#   DB.extension :sqls
#   DB[:table]
#   DB.sqls # =>  ["SELECT * FROM table LIMIT 1"]
#
# Related module: Sequel::Sqls

module Sequel

  module Sqls

    attr_reader :sqls

    # Record SQL statements when logging query.
    def log_connection_yield(sql, conn, args = nil)
      @sqls_mutex.synchronize { sqls.push(sql) }
      super
    end

    def self.extended(db)
      db.instance_exec do
        @sqls_mutex ||= Mutex.new
        @sqls ||= []
      end
    end

  end

  Database.register_extension(:sqls, Sqls)

end
