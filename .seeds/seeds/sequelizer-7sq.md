---
id: sequelizer-7sq
title: Should with_dataset put a caller's read-write catalog first on the search path?
status: captured
type: question
created_at: 2026-10-30T16:31:51.416334+00:00
updated_at: 2026-10-30T16:31:51.416334+00:00
---

## Proposal (from the t_shank session, relayed by jde, 2026-10-30)

t_shank attaches its read-write `working.duckdb` to the shared dataset database as catalog `working`. Inside `with_dataset`, it then sets the search path itself:

```ruby
db.set(search_path: "working.main,memory.main,dataset_<s>.<s>")
```

It proposes an option on `with_dataset` (for example `write_catalog:`) that puts a caller's catalog first on the search path. t_shank would then drop that code. This is a proposal. Ryan has not ruled on the API.

## Facts that bear on it (from the code at c1a545a)

- `with_dataset` sets the path to `memory.main,<catalog>.<schema>` on one held connection. It restores the previous path in an `ensure`.
- The first entry of the search path is where a CREATE without a catalog goes. Today that is `memory.main`.
- t_shank's own SET inside the block is undone by the `ensure` at the end of the block, so t_shank's workaround is correct today.
- Sequelizer does not attach `working`. The caller attaches it, so the caller owns its file and its READ_WRITE mode.

## Directions (not ruled)

- (a) Add `write_catalog:` to `with_dataset`. The path becomes `<write_catalog>.main,memory.main,<catalog>.<schema>`. Sequelizer does not attach the catalog. It only names it.
- (b) Add a general `search_path_prefix:` that takes a list of `catalog.schema` entries.
- (c) Change nothing. Callers that need a different path set it inside the block, as t_shank does.

Open question for (a) and (b): should Sequelizer check that the named catalog is attached, and raise a clear error if it is not?
