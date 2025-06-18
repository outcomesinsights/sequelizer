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