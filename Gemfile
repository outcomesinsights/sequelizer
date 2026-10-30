source "https://rubygems.org"

# Specify your gem's dependencies in sequelizer.gemspec
gemspec

# The dataset_db tests open real DuckDB files. sequel-duckdb does not depend on
# the duckdb driver gem, which builds against the DuckDB C library (libduckdb);
# CI installs that library with bin/install-libduckdb.
gem "duckdb", "~> 2.0"
gem "sequel-duckdb", "~> 0.4"
gem "sequel-hexspace", "~> 2.0"
