module Sequel

  module Funky

    class FunkyBase

      def initialize(db)
        @db = db
      end

      def to_strptime(format)
        return format if format =~ /%/

        format.gsub('yyyy', '%Y').gsub('MM', '%m').gsub('dd', '%d')
      end

      def from_strptime(format)
        return format unless format =~ /%/

        format.gsub('%Y', 'yyyy').gsub('%m', 'MM').gsub('%d', 'dd')
      end

    end

    class FunkySpark < FunkyBase

      def str_to_date(value, format, try: false) # rubocop:disable Lint/UnusedMethodArgument
        Sequel.function(:to_date, Sequel.cast_string(value), format)
      end

      def hash(*)
        Sequel.function(:xxhash64, *)
      end

      def make_json_column(ds, key_column, value_column)
        json_object_col = Sequel.function(
          :named_struct,
          'key',
          key_column,
          'value',
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

    end

    class FunkyDuckDB < FunkyBase

      def str_to_date(value, format, try: false)
        strptime_func = try ? :try_strptime : :strptime
        Sequel.function(strptime_func, Sequel.cast_string(value), to_strptime(format))
      end

      def hash(*)
        Sequel.function(:hash, concat(*)).then do |hash_val|
          Sequel.case(
            { hash_val <= 9_223_372_036_854_775_807 => hash_val },
            hash_val - 18_446_744_073_709_551_616,
          ).cast(:bigint)
        end
      end

      def concat(*)
        Sequel.function(:concat, *)
      end

      def make_json_column(ds, key_column, value_column)
        json_object_col = Sequel.function(
          :json_object,
          key_column,
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
