# Changelog

All notable changes to this project will be documented in this file.

## [0.4.0] - 2026-10-25

### Breaking changes

- **options:** Passed schema wins, and a caller's after_connect still runs ([8656edc](https://github.com/outcomesinsights/sequelizer/commit/8656edc9bf9d7a5d8f3c8242139c9f779af9b3e0)): when a lower-precedence source (.env, ENV or YAML) sets search_path and the caller passes schema: or schema_search_path:, the passed value is now the search path. Before, the lower-precedence search_path was used. A source that set schema while a lower-precedence source set search_path changes the same way.
- **funky:** Hash takes a named strategy, and md5 is the default ([5a8ef4e](https://github.com/outcomesinsights/sequelizer/commit/5a8ef4e6df604f40a943f15a30c1618fe08db27a)): funky.hash returns different ids by default. Pass strategy: :legacy to get the ids that earlier versions built.
- **smart_select_remove:** Raise AllColumnsRemovedError when every column is removed ([d8eeca4](https://github.com/outcomesinsights/sequelizer/commit/d8eeca42bbb5e365290bc4ea911e150ba9799d1f)): code that removed every column with select_remove got SELECT * and now raises AllColumnsRemovedError.
- **smart_select_remove:** Raise NoColumnsError instead of producing SELECT * ([810a0c7](https://github.com/outcomesinsights/sequelizer/commit/810a0c7fe8406683a185b129797d9818ba4c871e)): code that got SELECT * from select_remove on a database that returns no columns now raises NoColumnsError. conceptql loads this extension and builds SQL on Sequel.mock(host: :postgres) in its tests, so it may see this error when it moves to sequelizer 0.4.
- Drop hashie and OptionsHash for symbol-keyed hashes ([490c924](https://github.com/outcomesinsights/sequelizer/commit/490c924cba0c87d331607a49ed7dcb5963741e36)): Sequelizer.options and Options#to_hash now return a plain Hash with Symbol keys; look keys up with symbols (h[:adapter]).
- Remove the update_gemfile command and GemfileModifier ([4837ff4](https://github.com/outcomesinsights/sequelizer/commit/4837ff470477b8e092afaa9de612bf3cf7582580)): the update_gemfile command and Sequelizer::GemfileModifier are removed; use `bundle add <adapter gem>` instead.

### Added

- **settable:** Quote Sequel expression values and make set_sql public ([5882d41](https://github.com/outcomesinsights/sequelizer/commit/5882d416429d88a5cc08a391e249e51d76399770))

### Changed

- **deps:** Drop the activesupport runtime dependency ([3380d25](https://github.com/outcomesinsights/sequelizer/commit/3380d25805b5608fc87226eaf8a2521262aaa655))
- **deps:** Drop the pp dependency and require ([8f186b3](https://github.com/outcomesinsights/sequelizer/commit/8f186b34c2011382ed12a67e166dab909e99d93f))
- Delete empty ConnectionMaker#configure_adapter_specific_options ([33da14e](https://github.com/outcomesinsights/sequelizer/commit/33da14ed0ad8acd41026d4c9e27cba6c62fb1a2b))
- Apply db_opts without patching ConnectionPool#make_new ([3507790](https://github.com/outcomesinsights/sequelizer/commit/350779069a72e7def64717dbb93eb2266e1cde00))

### Fixed

- **sequelizer:** A URL string at new_db and db means { url: string } ([a2e6091](https://github.com/outcomesinsights/sequelizer/commit/a2e6091f735d9f496f521430fb9942898e4bae50))
- **connection_maker:** Raise MissingAdapterError when nothing is configured ([c531242](https://github.com/outcomesinsights/sequelizer/commit/c531242e84c66390effa145cea5e4412eabaaaf4))
- **options:** Accept a database URL string as the url option ([73c5f61](https://github.com/outcomesinsights/sequelizer/commit/73c5f61df0c3c2037605d3b53d9c301e087b1c32))
- **smart_select_remove:** Resolve an explicit select list without querying the database ([f23c851](https://github.com/outcomesinsights/sequelizer/commit/f23c851f1f3ef987bc41869d43e04bb776db44fc))

## [0.3.0] - 2026-10-01

### Breaking changes

- Drop support for Ruby 3.2 ([feef6de](https://github.com/outcomesinsights/sequelizer/commit/feef6de5c155dc0dd39642ad1686ff9bab0211de)): sequelizer now requires Ruby >= 3.3.0.

### Added

- Add smart_select_remove Sequel extension ([a1366ec](https://github.com/outcomesinsights/sequelizer/commit/a1366ec8f68e64728b3c794de15c2fd78cfa9e2e))
- DuckDB support in make_readyable and cold_col extensions ([9433d98](https://github.com/outcomesinsights/sequelizer/commit/9433d982bc0855df11ac6f48a915e861fd78a572))

### Changed

- Extract available_tables to fix AbcSize in ReadyMaker#run ([60c6a68](https://github.com/outcomesinsights/sequelizer/commit/60c6a6803afbfde2b0747fd19e3bcd346bf2d1ef))
- Simplify cold_col find_columns and remove rescue nil guards ([752eab1](https://github.com/outcomesinsights/sequelizer/commit/752eab14595af23974ea56a976dd99e29d9d5552))
- Remove OptionalAdapterSupport, add sequel-duckdb to bundle ([74d6d16](https://github.com/outcomesinsights/sequelizer/commit/74d6d16f564742138a32e111d7b6107289abec75))
- Let Sequel handle adapter loading, remove pre-require ([c2b592d](https://github.com/outcomesinsights/sequelizer/commit/c2b592d1965e24370dae2f5cfb515097358cd3da))
- Ship only runtime files in the gem: lib/, the sequelizer executable, the platform CSVs, and the docs and licence ([1cc49b6](https://github.com/outcomesinsights/sequelizer/commit/1cc49b69dec0c6c879a469f0774c1196c467ed17))

### Fixed

- Fall back to database query in cold_col for unregistered tables ([d07f7c5](https://github.com/outcomesinsights/sequelizer/commit/d07f7c5e482074e631828afbf558a767d6695b66))
- Replace rescue modifier with explicit begin/rescue in cold_col ([6fced2b](https://github.com/outcomesinsights/sequelizer/commit/6fced2b4957277b5c6d45fabf11e89d0b476a8e5))
- Handle string SQL in cold_col create_table_as and create_view_sql ([8f30602](https://github.com/outcomesinsights/sequelizer/commit/8f306028857e3838370fc623cd619a9a79c8c06f))
- Handle Array search_path in after_connect ([c376825](https://github.com/outcomesinsights/sequelizer/commit/c3768251695286668ca49dcbb84aa12c3bbb7f69))

## 0.2.0

### Added

- funky Sequel extension for database-specific function abstraction
- kvcsv as a runtime dependency
- Platform configuration fixtures in config/platforms/

### Changed

- Broadened activesupport dependency from ~> 7.0 to >= 7, < 9
- Broadened hashie dependency from ~> 3.2 to >= 3.2, < 6.0
- Broadened dotenv dependency from ~> 2.1 to >= 2.1, < 4.0
- Bumped sequel from 5.93.0 to 5.101.0
- Added multi-Ruby CI matrix (3.2, 3.3, 3.4, 4.0) with separate lint job

### Fixed

- Adapter extraction from URL scheme for search_path processing

## 0.1.6

### Removed

- JDBC adapter support (jdbc_hive2, jdbc_impala, jdbc_postgres) - not needed for foreseeable future
- Native Impala adapter support - not needed for foreseeable future
- Kerberos authentication functionality for enterprise databases
- CGI dependency used for URL escaping in JDBC connections
- 16 test methods related to JDBC and Impala adapters

### Added

- pg gem as development dependency to support PostgreSQL testing

### Changed

- Simplified ConnectionMaker class by removing adapter-specific configuration methods
- Improved test coverage from 84.95% to 93.54% by removing unused code paths
- Updated documentation to reflect focus on standard Sequel adapters

## 0.1.5

### Changed

- Better handling of multiple directories of files for make_ready

## [0.1.0] - 2016-11-08

### Added

- Connections are cached by options to avoid over-allocation
- URL or URI option represent connection string
- sequelizer.yml is passed through ERB

### Changed

- Format of this [CHANGELOG](http://keepachangelog.com/en/0.3.0/)
- Prefer environment variables over other options
- Use config/sequelizer.yml instead of config/database.yml

## [0.0.6] - 2015-08-21

### Added

- Support for ruby-oci8 (Oracle) in update_gemfile command
- Read user-level configuration from ~/.config/sequelizer/database.yml

### Fixed

- Bug where options passed as symbols where sometimes ignored.

## [0.0.5] - 2014-08-29

### Added

- Support for TinyTDS (SQL Server) in update_gemfile command

### Fixed

- timeout is always converted to integer before passing to Sequel.connect

## [0.0.4] - 2014-08-18

### Added

- `init_env` command to bin/sequelizer
- Prefer `search_path` over `schema_search_path` option

## [0.0.3] - 2014-07-10

### Added

- Ability to view configuration by running `sequelizer config`

## [0.0.2] - 2014-07-10

### Added

- This [CHANGELOG](http://keepachangelog.com/)
- Behavior to merge options from all sources (#3)
- Dependency on hashie gem
- Some tests for Sequelizer::Options
- Sequelizer::OptionsHash
- Reference to issues #1, #3 in README

### Fixed

- Prevented TestEnvConfig from polluting environment variables

## [0.0.1] - 2014-07-10

### Added

- The project itself

[0.4.0]: https://github.com/outcomesinsights/sequelizer/compare/v0.3.0...v0.4.0
