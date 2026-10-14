---
id: sequelizer-c85
title: "settable: quote SET values through the adapter's literalizer, and make set_sql public"
status: captured
type: idea
created_at: 2026-10-13T17:51:04.709549+00:00
updated_at: 2026-10-14T13:53:10.398085+00:00
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

## RULED 2026-10-14: the caller chooses which values are quoted

Ryan chose "Caller chooses" over two other options: quote only on DuckDB, or quote for all databases except Impala, Spark and PostgreSQL. In his words, the option was: "set_sql stays raw for plain strings, and quotes only values that a caller wraps (for example Sequel.lit or a marker). hew would quote its own DuckDB values. No database-type branch."

Why the seed's original plan was not taken: t_shank calls `db.set(search_path: "a,b,public")` and `db.set(enable_nestloop: :off)` on PostgreSQL. With `literal()` on every value, the first becomes `SET search_path='a,b,public'`, which PostgreSQL reads as ONE schema named `a,b,public`. The second becomes the quoted identifier `"off"`.

Other facts found on 2026-10-14:

- sequel_impala defines its own private raw `set_sql`. The settable extension overrides it, because extensions extend the Database instance after the adapter. db_opts always loads settable, so Impala uses sequelizer's `set_sql`.
- db_opts already quotes any value that contains a non-word character (`prep_value`) before it calls `set_sql`. A `set_sql` that quoted every value would quote those twice.

The marker (an agent's pick, not ruled by Ryan): a value that is a `Sequel::SQL::Expression` goes through `literal()`, and every other value is interpolated raw as before. The caller writes `DB.set(memory_limit: Sequel.expr("1GB"))`. This uses Sequel's own wrapper rather than a new class. Measured on sequel-duckdb 0.2.1 through `Sequel.mock(host: :duckdb)`:

```
Sequel.expr("1GB")  -> '1GB'
Sequel.expr("it's") -> 'it''s'
Sequel.expr(4)      -> 4
Sequel.expr(true)   -> TRUE
"#{Sequel.expr('1GB')}" -> #<Sequel::SQL::StringExpression:0x...>   (today's output: invalid SQL, so no caller depends on it)
```

`Sequel.lit` is a String subclass, not an Expression, so it stays raw. That matches its meaning.

The open question on Impala and Spark is now moot. Plain values keep today's raw form on every database.
