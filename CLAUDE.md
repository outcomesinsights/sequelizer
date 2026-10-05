# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Sequelizer is a Ruby gem that simplifies database connections using Sequel. It allows users to configure database connections via config/database.yml or .env files, providing an easy-to-use interface for establishing database connections without hardcoding sensitive information.

The gem includes:

- A main module that provides `db` (cached connection) and `new_db` (fresh connection) methods
- CLI commands for configuration management and Gemfile updating
- Connections for any Sequel adapter (PostgreSQL, DuckDB, Spark via sequel-hexspace, ...)
- Sequel extensions for enhanced functionality, including the Platform abstraction

## Development Commands

### Testing

```bash
# Run all tests
bundle exec rake test

# Run tests with coverage report (generates coverage/index.html)
bundle exec rake coverage

# Run specific test file
bundle exec ruby -I lib test/lib/sequelizer/test_connection_maker.rb
```

### Linting and Formatting

The recipes follow the fleet standard (gator's standard/, seed gator-rga):

```bash
just setup      # mise install (pinned tools, mise.toml) + bundle install
just fmt        # treefmt: every tracked file, every language (treefmt.toml)
just fmt-check  # treefmt --fail-on-change: formats, then FAILS if anything changed
just lint       # rubocop, shellcheck, actionlint, zizmor --offline, hadolint, cog check
just ci         # fmt-check lint test hygiene: the full local CI equivalent
```

### Git Hooks

The hooks are untracked files in `.git/hooks/`, shared by every worktree:

- `pre-commit`: beads' managed block, then `just pre-commit` (fmt-check, lint, test,
  hygiene; about 5s). If fmt-check reformats anything, the commit fails: re-stage the
  changes and commit again.
- `pre-push`: `just pre-push` (the full `ci`), then `bd dolt push` to publish beads.

Never skip them with `--no-verify`; a failing hook is a real problem to fix.

### Build and Release

```bash
# Build gem (into pkg/)
bundle exec rake build
```

Releases publish only from `.github/workflows/release.yml` when a `v*` tag is
pushed. `rake release` is disabled, and nothing is ever `gem push`ed from a
workstation. To release:

1. Bump `VERSION` in `lib/sequelizer/version.rb` and run `bundle install`.
2. Add the changelog section with `git-cliff --unreleased --bump` (see
   `cliff.toml`), dropping entries for commits that change no shipped file.
3. Land that commit on `main` and wait for CI to pass on it.
4. Push the matching tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.

The workflow refuses unless the tag equals `v` + `VERSION`, the commit is on
`main`, and CI from a push to `main` passed on that exact commit. `v*` tags
cannot be deleted or moved, so a bad release is fixed with a new version.

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

- **cold_col**: column information for datasets without querying a live database
- **db_opts**: database-specific configuration options
- **funky**: database-specific function translations (e.g. Spark date parsing)
- **make_readyable**: prepares a database for use (temporary views, schema setup), mainly
  for Spark SQL and DuckDB
- **more_sql**: additional SQL helper methods
- **platform**: one interface for platform-specific behaviour. Capabilities and preferences
  come from `config/platforms/*.csv`, which ship in the gem and are loaded at runtime from
  the installed gem directory, so they must stay in the gemspec's file list.
- **settable**: a `set` method on connections
- **smart_select_remove**: `select_remove` that resolves columns from the dataset's
  expression tree before falling back to querying
- **sql_recorder**: records each SQL statement sent to the database
- **unionize**: efficient handling of large UNION operations
- **usable**: a `use` method for switching database/schema context

### Database Support

- PostgreSQL, with search_path/schema handling in `Sequelizer::Options`
- Any other Sequel adapter by URL or options, for example DuckDB (sequel-duckdb) and Spark
  (sequel-hexspace), which the test suite exercises through mock connections

### Test Structure

- Tests use Minitest framework
- Located in `test/` directory with subdirectories mirroring `lib/` structure
- Helper utilities in `test_helper.rb` including constant stubbing for testing

## Coding Standards

Style is whatever `.rubocop.yml` enforces: the fleet's ruled config, rubocop-rails-omakase
plus the Lint department (gator's standard/rubocop.yml). Run `bundle exec rubocop -a`
rather than formatting by hand; where this section and RuboCop disagree, RuboCop wins.

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

- Double quotes: `"postgres"`, `"SET #{key}=#{value}"` (omakase's Style/StringLiterals)

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

## Ruby Sequel as Lodestone

- Refer frequently to GitHub's jeremyevans/sequel repository for:
  - Examples of great documenation
  - Good code organization
  - Great commit messages
  - Wonderful changelog messages

## Platform Abstraction

The `platform` extension is implemented and shipped: `DB.extension :platform` gives a
`DB.platform` with `supports?` / `prefers?` / `[]` answers read from
`config/platforms/base.csv` and `config/platforms/rdbms/<adapter>.csv`, plus function
translations in code. Its design history (ADRs) lives in the oimnibus repository, not here.
Open beads extend it (consolidating extensions from other OI repos; `bd ready`).

## Agent Rules

1. **NEVER skip, hide, or conditionally disable tests to avoid failures.** If a test fails because a dependency is missing, add the dependency. If a test fails because fixture data is missing, create the fixtures. Wrapping a `require` in `rescue LoadError` and returning early is just as bad as deleting the test. Fix the root cause.
2. **NEVER exclude files from coverage to dodge SimpleCov thresholds.** If coverage is low because tests aren't running, make the tests run.
3. **Always test locally across all supported Ruby versions before pushing.** Use `MISE_RUBY_VERSION=X.Y mise exec -- bundle exec rake test` for each version in the CI matrix (3.3, 3.4, 4.0).
4. **Run `just ci` before every push** (the pre-push hook does, and CI runs the same recipes). No exceptions.

## Development Memories

- Ensure that bundler is used for all ruby/rake related cli invocations
- Read-only operations (exploration, testing) can be done in main directory
- Refer to Ruby Sequel for code style, test frameworks, and general guidance
- To test CLI, just call bundle exec bin/sequelizer without installing binstubs
- **IMPORTANT**: Commands like `docker build`, `devcontainer build`, and `bundle install` can take more than 10 minutes to complete and should be run with extended timeout (e.g., 20 minutes / 1200000ms)
- **Wait for explicit instructions before reading files or creating plans - do not be proactive**
- The only remote is `origin` (github.com/outcomesinsights/sequelizer). Push only when Ryan
  explicitly asks; the pre-push hook runs the full `just ci` and publishes beads.
