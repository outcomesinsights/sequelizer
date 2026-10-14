---
id: sequelizer-2jb
title: 'smart_select_remove: raise instead of SELECT * when the fallback finds no columns?'
status: captured
type: question
created_at: 2026-10-14T17:31:06.348455+00:00
updated_at: 2026-10-14T17:31:06.348455+00:00
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
