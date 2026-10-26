module Sequel
  module Funky
    # Raised when funky.hash is given a strategy name it does not know.
    class UnknownHashStrategyError < Sequel::Error
      def initialize(strategy)
        super("unknown funky.hash strategy #{strategy.inspect}; known strategies: #{FunkyBase::HASH_STRATEGIES.map(&:inspect).join(", ")}")
      end
    end

    class FunkyBase
      # The names funky.hash accepts. A strategy's definition never changes,
      # because a change would change every id built with it; a new
      # definition gets a new name.
      HASH_STRATEGIES = %i[md5 legacy].freeze

      # ASCII unit separator: joins the parts in the md5 strategy.
      HASH_SEPARATOR = 31

      # ASCII record separator: stands in for a NULL part in the md5 strategy.
      HASH_NULL_MARKER = 30

      def initialize(db)
        @db = db
      end

      # Returns a signed 64-bit integer expression that hashes +parts+.
      #
      # strategy: :md5 (the default) casts each part to a string, writes a NULL
      # part as chr(30), joins the parts with chr(31), and reads the first 16
      # hex characters of their md5 as a signed integer. It gives the same id
      # on DuckDB and on Spark when each part turns into the same string on
      # both. Measured on DuckDB 1.5 and Spark 3.5, that is true for strings,
      # integers, booleans, decimals, dates, timestamps without a time zone,
      # and doubles that are zero or from 0.001 up to (not including)
      # 10,000,000 in absolute value. It is false for other doubles, which
      # Spark writes in E notation (1.0E7) and DuckDB does not (10000000.0),
      # and for DuckDB's TIMESTAMPTZ, whose text ends in a UTC offset.
      # Before you pass such a part, cast a TIMESTAMPTZ to a timestamp, and
      # cast a double to a decimal. The decimal gives the same text for
      # 123456789.5, but not for 1e20 at DECIMAL(38,6), where DuckDB keeps
      # the double's rounding error.
      #
      # strategy: :legacy is each database's form before :md5 existed:
      # hash(concat(...)) on DuckDB and xxhash64(...) on Spark. Use it only to
      # reproduce ids built with it; on DuckDB it gives duplicate ids.
      def hash(*parts, strategy: :md5)
        case strategy
        when :md5 then md5_hash(parts)
        when :legacy then legacy_hash(parts)
        else raise UnknownHashStrategyError, strategy
        end
      end

      def to_strptime(format)
        return format if format =~ /%/

        format.gsub("yyyy", "%Y").gsub("MM", "%m").gsub("dd", "%d")
      end

      def from_strptime(format)
        return format unless format =~ /%/

        format.gsub("%Y", "yyyy").gsub("%m", "MM").gsub("%d", "dd")
      end

      private

      # The first 16 hex characters of the md5 of the joined parts.
      def md5_hex16(parts)
        strings = parts.map do |part|
          Sequel.function(:coalesce, Sequel.cast_string(part), Sequel.function(:chr, HASH_NULL_MARKER))
        end
        joined = Sequel.function(:concat_ws, Sequel.function(:chr, HASH_SEPARATOR), *strings)
        Sequel.function(:substr, Sequel.function(:md5, joined), 1, 16)
      end
    end

    class FunkySpark < FunkyBase
      def str_to_date(value, format, try: false) # rubocop:disable Lint/UnusedMethodArgument
        Sequel.function(:to_date, Sequel.cast_string(value), format)
      end

      def make_json_column(ds, key_column, value_column)
        json_object_col = Sequel.function(
          :named_struct,
          "key",
          key_column,
          "value",
          value_column,
        ).then do |json_object_col|
          Sequel.function(
            :collect_list,
            json_object_col,
          )
        end.then do |list_col|
          Sequel.function(
            :map_from_entries,
            list_col,
          )
        end.then do |map_from_entries_col|
          Sequel.function(
            :to_json,
            map_from_entries_col,
          )
        end
        ds.from_self
          .select(json_object_col)
          .limit(1)
      end

      def collect_list(column)
        Sequel.function(:collect_list, column)
      end

      private

      # conv with a negative target base reads the hex as a signed number.
      def md5_hash(parts)
        Sequel.function(:conv, md5_hex16(parts), 16, -10).cast(:bigint)
      end

      def legacy_hash(parts)
        Sequel.function(:xxhash64, *parts)
      end
    end

    class FunkyDuckDB < FunkyBase
      def str_to_date(value, format, try: false)
        strptime_func = try ? :try_strptime : :strptime
        Sequel.function(strptime_func, Sequel.cast_string(value), to_strptime(format))
      end

      def concat(*)
        Sequel.function(:concat, *)
      end

      def make_json_column(ds, key_column, value_column)
        json_object_col = Sequel.function(
          :json_object,
          Sequel.cast_string(key_column),
          value_column,
        ).then do |json_object_col|
          Sequel.function(
            :list,
            json_object_col,
          )
        end
        ds.from_self
          .select(json_object_col)
          .limit(1)
      end

      def collect_list(column)
        Sequel.function(:list, column)
      end

      private

      def md5_hash(parts)
        signed(Sequel.cast(Sequel.join([ "0x", md5_hex16(parts) ]), :ubigint))
      end

      def legacy_hash(parts)
        signed(Sequel.function(:hash, concat(*parts)))
      end

      # Folds a UBIGINT into the BIGINT with the same 64 bits.
      def signed(ubigint)
        Sequel.case(
          { ubigint <= 9_223_372_036_854_775_807 => ubigint },
          ubigint - 18_446_744_073_709_551_616,
        ).cast(:bigint)
      end
    end

    def self.extended(db)
      db.instance_exec do
        @funky = get_funky(db.database_type)
      end
    end

    def funky
      @funky
    end

    def get_funky(database_type)
      case database_type
      when :spark
        FunkySpark.new(self)
      when :duckdb
        FunkyDuckDB.new(self)
      else
        raise "No known functions for #{database_type}"
      end
    end
  end

  Database.register_extension(:funky, Funky)
end
