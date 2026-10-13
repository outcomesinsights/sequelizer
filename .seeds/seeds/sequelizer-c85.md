---
id: sequelizer-c85
title: "settable: quote SET values through the adapter's literalizer, and make set_sql public"
status: captured
type: idea
created_at: 2026-10-13T17:51:04.709549+00:00
updated_at: 2026-10-13T17:51:04.709549+00:00
tags:
  - settable
  - duckdb
---

## Problem

The `settable` extension (`Database#set(opts)`) builds `SET key=value` by plain string interpolation, in the private `set_sql`. It does not pass the value through the adapter's literalizer. `db_opts` loads `settable` automatically.

Measured on a real in-memory DuckDB through sequel-duckdb 0.3.1 on 2026-10-13:

- `SET threads=4` runs.
- `SET memory_limit=1GB` fails with `Parser Error: syntax error at or near "GB"`.
- `SET memory_limit='1GB'` runs.
- `SET timezone=America/Los_Angeles` fails with `Binder Error: SET value cannot contain column names`.

So `Database#set` is broken for DuckDB string values today.

## Proposal (Ryan accepted the placement on 2026-10-13)

1. `set_sql` uses `literal(value)` for databases whose SET takes an SQL literal. On sequel-duckdb, `literal` gives `'1GB'`, `'it''s'`, `4` and `TRUE`, which are all valid.
2. `set_sql` becomes public, so a caller can get the SQL text without running it. This follows Sequel's convention of a public `*_sql` twin, such as `insert_sql`. hew needs the text for DuckDB CLI `-cmd` arguments.

## Open question: Impala and Spark (not verified)

sequelizer was written mostly for Impala and Spark. Their SET statements may take the value as raw text, and then quoting would put the quotes into the value. Test this on Impala and Spark before you change the behaviour for them. If they need the raw form, branch on `db.database_type`, as Sequel's `date_arithmetic` extension does, and quote for the others.

## Not in scope

`set_pragma` stays in the sequel-duckdb adapter. PRAGMA is specific to DuckDB and SQLite, and Sequel puts such statements in the adapter. The parent deliberation is sequel-duckdb's seed sequel-duckdb-pbj ("DuckDB DSL features requested by hew to remove raw SQL").
