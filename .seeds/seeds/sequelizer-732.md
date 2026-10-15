---
id: sequelizer-732
title: funky.hash on DuckDB gives duplicate ids; should the hash strategy be selectable?
status: captured
type: question
created_at: 2026-10-15T22:55:14.998273+00:00
updated_at: 2026-10-15T22:56:05.891341+00:00
---

## The defect (reported by the roobetl session, 2026-10-14)

roobetl makes every GDM id with `db.funky.hash(...)`. On DuckDB that hash gives duplicate ids at a rate far above what a good 64-bit hash gives. The design of a fix is NOT ruled.

The two implementations differ, verified in `lib/sequel/extensions/funky.rb` at sequelizer 09f9194:

```ruby
# FunkySpark#hash
Sequel.function(:xxhash64, *)

# FunkyDuckDB#hash
Sequel.function(:hash, concat(*)).then do |hash_val|
  Sequel.case(
    { hash_val <= 9_223_372_036_854_775_807 => hash_val },
    hash_val - 18_446_744_073_709_551_616,
  ).cast(:bigint)
end
```

So one row already gets a different id on Spark and on DuckDB. Spark hashes the separate arguments. DuckDB hashes one string made by `concat` with no separator, then folds the UBIGINT result to a signed bigint.

## Evidence (from roobetl, seer_medicare_lung_2026 ETL, sequelizer at 1013851)

- February full run: `clinical_codes` had 18 duplicate ids in 595,557,041 rows, and `collections` had 2 in 77,764,208 rows.
- A good 64-bit hash gives about 0.01 expected collisions for 595M rows. The observed count is about 1,900 times that.
- 5,000-patient sample, one generator: 63,503 distinct concat strings gave 63,502 distinct `hash()` values. The strings were all distinct, so DuckDB's `hash()` itself collided. The missing separator was not the cause in this sample.
- A second, separate hazard: `concat` with no separator gives the same input for ("1","23") and ("12","3"). roobetl found no case of this in its data.
- On the same 63,503 keys, each of these gave 0 collisions: `hash(concat_ws('/', ...))`, `md5_number_upper(concat_ws('/', ...))`, `md5_number_lower(...)`, and the full `md5_number`. On DuckDB, `md5_number_upper` returns UBIGINT and needs the same signed fold.

## Callers (checked 2026-10-15)

- roobetl calls `funky.hash` in 7 places, in 3 files. `transformations/modifier_function.rb` has 4: `make_id` (line 194), `make_id_from_row` (201), `get_ids_from_oi_raw_id` (60) and `get_ids_from_source` (64). `make_id` and `make_id_from_row` make the GDM ids. `post_processors/base_processor.rb` has 2 (lines 46 and 165), and `post_processors/seer_information_periods.rb` has 1 (line 35).
- No caller was found in conceptql, t_shank, summarb or jigsaw-diagram-editor. The only t_shank match is a copy of sequelizer's own test under t_shank's `claude_stuff/`.

## The design question (Ryan's)

Should `funky.hash` take the name of the hash function, with a sensible default, so that a later change does not need a sequelizer change?

## The roobetl session's recommendation (NOT ruled)

- Use a named, versioned strategy, not a bare function name. The DuckDB expression needs a separator and the signed fold, and a bare function name cannot express either.
- Keep the current strategy as the default, so no existing caller's ids change without notice. roobetl opts in to the new strategy.
- Consider an md5-based strategy that gives the same ids on both engines. Spark has `md5`, so `substr(md5(x), 1, 16)` can become a bigint there. UNVERIFIED: not tested on Spark.
- A change of strategy changes every id. So it must be the caller's choice, and it must be visible in the call or in the config.

## Hazard

If the default changes, every caller of `funky.hash` gets new ids. Today that is roobetl only (7 calls), by the search above.
