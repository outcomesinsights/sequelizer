---
id: sequelizer-2jb
title: 'smart_select_remove: raise instead of SELECT * when the fallback finds no columns?'
status: resolved
type: question
created_at: 2026-10-14T17:31:06.348455+00:00
updated_at: 2026-10-14T19:46:41.495143+00:00
resolved_at: 2026-10-14T19:46:41.495133+00:00
resolution: "Ruled (a), raise. Shipped as bead sequelizer-uqk, commit 810a0c7, merged to local main as ed70ada with sequelizer-ovw. Not pushed. lib/sequel/extensions/smart_select_remove.rb:32 defines Sequel::SmartSelectRemove::NoColumnsError, and select_remove raises it before its single fallback super when columns is empty. Verified on main: hew's explicit-select case gives SELECT \"a\", \"partition_id\" FROM \"t\" with no query, and a bare dataset on Sequel.mock raises NoColumnsError. Efficacy: tweaking needed: minor. The bead text claimed that a bare or qualified star does not resolve, but resolve_outer_column_name returned :* for it. The agent made the star unresolvable, which also changed the from_self path (a planning miss: the bead author did not check the helper's Symbol branch). Open after this: removing EVERY column of a non-empty list still renders SELECT *. The ruling limited the raise to zero resolved columns, so this was not changed."
tags:
  - smart_select_remove
  - hew
---

## Question

When `select_remove` cannot resolve columns statically and falls back to Sequel's `select_remove`, Sequel calls `columns`. On `Sequel.mock`, or on any connection that returns no columns, the result is `select()` with no arguments, which renders as `SELECT *`. The removed column comes back, with no error.

Should smart_select_remove raise when the fallback yields no columns, instead of producing `SELECT *`?

## Context

Found on 2026-10-14 from hew's defect report. hew generates DuckDB SQL from `Sequel.mock`. Bead sequelizer-ovw fixes the common case (an explicit select list made of plain columns, qualified columns and aliases). After that fix, the silent `SELECT *` can still happen for a select list with an entry it cannot resolve (`Sequel.lit`, `*`), or for a bare dataset with no select list.

Not ruled. Directions:

- (a) Raise an error when the fallback resolves zero columns. It is loud, but it differs from Sequel's own `select_remove`.
- (b) Keep Sequel's behaviour and document the hazard in the extension header.
- (c) Raise only when the removed column is not among the resolved columns. A mock returns none, so on a mock this is the same as (a).

## RULED 2026-10-14: raise (direction a)

Ryan: "if this is our version of select remove, we can do what we want, so if you think raising is better, let's raise." The agent had recommended raising, because a silent `SELECT *` returns wrong data with no error.

Consequences found on 2026-10-14, before the bead was written:

- Three existing tests in `test/lib/sequel/extensions/test_smart_select_remove.rb` reach the fallback on a plain `Sequel.mock`, which returns no columns: `test_falls_back_for_bare_dataset`, `test_falls_back_for_unresolvable_expression`, and (after sequelizer-ovw) the explicit-select fallback test. Their mock must supply columns (`Sequel.mock(columns: [...])`) so that they still test the fallback. That is a fixture change that follows from the ruling, not a weakened test.
- conceptql loads smart_select_remove (`lib/conceptql/database.rb`), calls `select_remove` in three operators, and builds SQL on `Sequel.mock(host: :postgres)` in its tests. Any conceptql test that reaches the fallback today gets `SELECT *` silently, and will raise after this change. conceptql pins `sequelizer >= 0.3.0, < 0.4`, so it sees the change only when it moves to 0.4.
- The change is breaking, so its commit is marked `!`.
