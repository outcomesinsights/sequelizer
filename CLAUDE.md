# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Sequelizer is a Ruby gem that simplifies database connections using Sequel. It allows users to configure database connections via config/database.yml or .env files, providing an easy-to-use interface for establishing database connections without hardcoding sensitive information.

The gem includes:
- A main module that provides `db` (cached connection) and `new_db` (fresh connection) methods
- CLI commands for configuration management and Gemfile updating
- Support for multiple database adapters including PostgreSQL, Impala, and Hive2
- Sequel extensions for enhanced functionality

## Development Commands

### Testing
```bash
# Run all tests
rake test

# Run specific test file
ruby -I lib test/lib/sequelizer/test_connection_maker.rb
```

### Build and Release
```bash
# Build gem
rake build

# Release gem
rake release
```

### CLI Commands
```bash
# Show current configuration
bundle exec sequelizer config

# Update Gemfile with database adapter
bundle exec sequelizer update_gemfile

# Initialize .env file
bundle exec sequelizer init_env --adapter postgres --host localhost --database mydb
```

## Architecture

### Core Components

- **Sequelizer module** (`lib/sequelizer.rb`): Main interface providing `db` and `new_db` methods
- **ConnectionMaker** (`lib/sequelizer/connection_maker.rb`): Handles database connection logic and adapter-specific configurations
- **Options** (`lib/sequelizer/options.rb`): Manages configuration from multiple sources with precedence order
- **CLI** (`lib/sequelizer/cli.rb`): Thor-based command line interface

### Configuration Sources (in precedence order)
1. Passed options
2. .env file
3. Environment variables
4. config/database.yml
5. ~/.config/sequelizer/database.yml

### Sequel Extensions
Located in `lib/sequel/extensions/`:
- **db_opts**: Database-specific options handling
- **make_readyable**: Readiness checking functionality
- **settable**: Dynamic property setting
- **sqls**: SQL statement management
- **usable**: Connection usability features

### Database Support
The gem supports various database adapters with special handling for:
- PostgreSQL (including search_path/schema management)
- JDBC-based connections (Hive2, Impala, PostgreSQL)
- Kerberos authentication for enterprise databases

### Test Structure
- Tests use Minitest framework
- Located in `test/` directory with subdirectories mirroring `lib/` structure
- Helper utilities in `test_helper.rb` including constant stubbing for testing

## Coding Standards

This project follows standard Ruby community conventions without formal linting rules, emphasizing readability, consistency, and Ruby idioms.

### Style Conventions

**Indentation & Formatting:**
- 2-space indentation (no tabs)
- Single-line method definitions when appropriate: `def e(v)`
- Method parameters without parentheses when no arguments: `def connection`
- Method parameters with parentheses when there are arguments: `def initialize(options = nil)`

**Naming:**
- Module/Class names: PascalCase (`Sequelizer`, `ConnectionMaker`)
- Method names: snake_case (`new_db`, `find_cached`, `after_connect`)
- Variable names: snake_case (`sequelizer_options`, `db_config`)
- Instance variables: snake_case with `@` prefix (`@options`, `@_sequelizer_db`)
- Constants: SCREAMING_SNAKE_CASE (`VERSION`)

**Strings:**
- Single quotes for simple strings: `'postgres'`, `'mock'`
- Double quotes for interpolation: `"SET #{key}=#{value}"`

### Code Organization

**File Structure:**
- One main class/module per file
- Nested modules follow directory structure: `lib/sequelizer/connection_maker.rb`
- Private methods grouped at bottom with `private` keyword

**Dependencies:**
- Use `require_relative` for internal dependencies: `require_relative 'sequelizer/version'`
- Use `require` for external gems: `require 'sequel'`, `require 'thor'`
- Group requires at top of files

### Documentation

**Comments:**
- Use `#` for single-line comments
- Extensive method documentation with parameter descriptions
- Minimal inline comments, used for clarification of complex logic

### Ruby Idioms

**Patterns Used:**
- Memoization: `@_sequelizer_db ||= new_db(options)`
- Conditional assignment: `||=` for defaults
- Metaprogramming with `define_method` for dynamic method creation
- Symbol keys in hashes: `{ adapter: 'postgres' }`
- Method chaining kept readable

**Testing Patterns:**
- Test methods prefixed with `test_`: `def test_accepts_options_as_params`
- Extensive use of stubbing and mocking for isolated testing
- Custom helper methods for common setup patterns