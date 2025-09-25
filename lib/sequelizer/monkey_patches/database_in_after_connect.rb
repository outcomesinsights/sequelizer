module Sequel
  class ConnectionPool

    # Return a new connection by calling the connection proc with the given server name,
    # and checking for connection errors.
    def make_new(server)
      begin
        conn = @db.connect(server)
        if (ac = @after_connect)
          case ac.arity
          when 3
            ac.call(conn, server, @db)
          when 2
            ac.call(conn, server)
          else
            ac.call(conn)
          end
        end
      rescue StandardError => e
        raise Sequel.convert_exception_class(e, Sequel::DatabaseConnectionError)
      end
      raise(Sequel::DatabaseConnectionError, 'Connection parameters not valid') unless conn

      conn
    end

  end
end
