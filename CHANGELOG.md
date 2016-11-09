# Changelog
All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Connections are cached by options to avoid over-allocation

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
