# Sequelizer [![CI](https://github.com/outcomesinsights/sequelizer/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/outcomesinsights/sequelizer/actions/workflows/test.yml)

I was tired of writing the code to bootstrap a connection to my databases.

[Sequel](https://github.com/jeremyevans/sequel/) provides an easy mechanism for connecting to a database, but I didn't want to store my username/password/other sensitive information in the scripts I was writing.

So I wrote this gem that lets me store my database configuration options in either config/sequelizer.yml or .env and then lets me call `db` to get a connection to my database.

I normally use this gem when I'm writing a quick script or a Thor-based command line utility.

## Installation

Add this line to your application's Gemfile:

```
gem 'sequelizer'
```

And then execute:

```
$ bundle
```

Or install it yourself as:

```
$ gem install sequelizer
```

## Usage

To get the most out of Sequelizer, you'll need to create a config/sequelizer.yml file or a .env file and specify your database configuration options in that file.

Sequelizer comes with a handy command that will print out your connection parameters. Just run:

```
bundle exec sequelizer config
```

You'll also need to make sure the gem for your database is installed. You can do this by adding the gem to your application's Gemfile, e.g. for PostgreSQL:

```
bundle add pg
```

Once you've specified your options and made sure your database's gem is installed, simply include the Sequelizer module in any class that needs a database connection and you'll get two handy-dandy methods: `db` and `new_db`

Observe:

```ruby
require 'sequelizer'

class ClassThatNeedsSomeDBLove
  include Sequelizer

  def my_super_cool_method_that_needs_to_talk_to_a_db
    db[:my_awesome_table].join(
      db[:another_great_table].select(:an_important_column),
      [:an_important_column])
  end
end
```

`db` will create a new connection to the database and cache that connection so that subsequent calls to `db` will use the same connection.

`new_db` will create a new connection to the database on each call.

Both take a hash of database options, or a database URL string such as `"postgres://localhost/my_db"`, if you don't want to create a config/sequelizer.yml or .env file, or simply wish to override those options. Options are merged together from all sources with the following precedence:

```
passed_options > .env > manually defined environment variables > config/sequelizer.yml > ~/.config/sequelizer/database.yml
```

So if config/sequelizer.yml specifies a connection, you can set an environment variable (either manually, or through .env) to override one of those options. Similarly, if you pass an option to the method directly, that option will override the YAML and ENV-based options. See #3 for further discussion.

For PostgreSQL, `search_path`, `schema_search_path` and `schema` are three names for one option. The highest-precedence source that sets any of them decides the search path, so a `schema:` you pass overrides a `search_path` from .env or YAML. If one source sets more than one name, `search_path` wins over `schema_search_path`, which wins over `schema`. Sequelizer creates the schemas and sets the search path on each new connection, and then runs any `after_connect` you pass.

Take a look at the examples directory for a few ways you can specify your database configuration options. Copy a `sequelizer*.yml` example to `config/sequelizer.yml` to use it.

## Loading Sequel extensions

An option named `extension_<name>` loads the Sequel extension `<name>` on each connection that Sequelizer makes. The option's value does not matter. For example, this line in .env loads `funky`:

```
SEQUELIZER_EXTENSION_FUNKY=1
```

In config/sequelizer.yml, write `extension_funky: 1`. You can also load an extension yourself with `db.extension :funky`.

An option named `<database type>_db_opt_<setting>` becomes a `SET <setting>=<value>` statement on each new connection. For example, `postgres_db_opt_work_mem: 256MB` runs `SET work_mem=256MB`.

## Sequel extensions

Sequelizer ships these Sequel extensions. You can load each one on any Sequel connection, not only on one that Sequelizer made.

- **cold_col**: gives the columns of a dataset without a query to the database. It reads table schemas from a YAML file (`db.load_schema`), from `db.add_table_schema`, and from the tables and views that the session creates.
- **db_opts**: applies the `<database type>_db_opt_<setting>` options above. Sequelizer loads it on every connection.
- **funky**: functions that are written differently on Spark and on DuckDB, through `db.funky`. It supports only those two databases, and it raises an error on any other.
  - `db.funky.hash(*parts)` returns a signed 64-bit integer that hashes the parts. The default strategy, `:md5`, gives the same id on DuckDB and on Spark when each part turns into the same string on both. That is true for strings, integers, booleans, decimals, dates and timestamps without a time zone. It is false for doubles of 10,000,000 or more, or under 0.001, in absolute value, and for DuckDB's TIMESTAMPTZ. Cast such a part to a decimal or a timestamp first.
  - `db.funky.hash(*parts, strategy: :legacy)` gives the ids that sequelizer 0.3 and earlier built. Use it only to reproduce those ids, because on DuckDB it gives duplicate ids. An unknown strategy raises `Sequel::Funky::UnknownHashStrategyError`.
  - `str_to_date(value, format)`, `collect_list(column)` and `make_json_column(dataset, key_column, value_column)` write the same operation for each database.
- **make_readyable**: `db.make_ready(use_schema:, search_path:, only:, except:)` prepares a Spark or DuckDB database for queries. It creates temporary views for the tables in a list of schemas, in order of precedence, and for external Parquet, ORC or other files given as `Pathname`s.
- **more_sql**: `db.create_schema(name, if_not_exists: true)`.
- **platform**: `db.platform` answers what the database supports and prefers (`supports?(:cte)`, `prefers?(:parquet)`, `[:interim_schema]`), and translates functions such as `date_diff(from, to)` and `days_between(from, to)`. The answers come from the CSV files in config/platforms/.
- **settable**: `db.set(timezone: "UTC")` runs `SET timezone=UTC`. A value is written into the statement as it is. Wrap a value in `Sequel.expr` when the database needs a quoted literal. `db.set_sql` returns the statements and runs nothing.
- **smart_select_remove**: replaces Sequel's `select_remove`. It finds the columns from the dataset's own SELECT list, or through `from_self` chains, so it does not need to query the database. It raises `Sequel::SmartSelectRemove::NoColumnsError` when it cannot find the columns, and `Sequel::SmartSelectRemove::AllColumnsRemovedError` when every column would be removed. In both cases Sequel's own `select_remove` would produce `SELECT *`, which still contains the removed columns.
- **sql_recorder**: `db.sql_recorder` is an array of every SQL statement sent to the database. Call `db.sql_recorder.clear` to empty it.
- **unionize**: `db.unionize(datasets, chunk_size: 100, all: true)` combines many datasets with UNION, one chunk at a time, for databases that cannot run one very large UNION. Each chunk goes into a temporary view on Spark and a temporary table on DuckDB. It supports only those two databases.
- **usable**: `db.use(:my_schema)` runs a USE statement that switches to that schema.

## Frustrations

I can't seem to figure out a way to avoid having to specify the database gem in the a user's bundler file. If anyone has ideas on how to automagically load the correct database gem based on the database options fed to Sequelizer, please let me know (#1)!

## Contributing

1. Fork it ( http://github.com/outcomesinsights/sequelizer/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Thanks

- [Outcomes Insights, Inc.](http://outins.com)
  - Many thanks for allowing me to release a portion of my work as Open Source Software!
- Jeremy Evans
  - For writing Sequel!

## License

Released under the MIT license, Copyright (c) 2014 Outcomes Insights, Inc.
