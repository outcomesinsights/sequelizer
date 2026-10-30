---
id: sequelizer-4df
title: 'dataset_db review: six findings and the rulings on them'
status: resolved
type: decision
created_at: 2026-10-30T12:10:22.758348+00:00
updated_at: 2026-10-30T12:19:53.330406+00:00
resolved_at: 2026-10-30T12:19:53.330395+00:00
resolution: All six findings fixed on main at 1e6e053; beads sequelizer-ttu, -m9c, -f7a, -asi, -n5w, -dj4 closed
tags:
  - dataset_db
  - duckdb
  - review
---

An adversarial review on 2026-10-30 of `Sequelizer.dataset_db` (bead sequelizer-gpz, released as 0.4.1, commits 0b8eadd, acf8ac8, 6811594) found six problems. It found no crash and no data loss. CI and Release passed on 3be0131, and 0.4.1 is on rubygems.

## What the review checked

- The diffs of the three commits.
- sequel-duckdb 0.4.2: an in-memory database is opened once in `adapter_initialize` and is shared by every pool connection. `disconnect` does not close an in-memory database. In-memory databases are not in `InstanceRegistry`.
- t_shank's original, `lib/t_shank/data_stores/duckdb_directory.rb`. It had a `disconnect` that detached the dataset and disconnected. The port has no equivalent.
- The caller in jigsaw-diagram-editor: `DataStore#duckdb_dataset_db`. Puma runs 2 workers with `preload_app!`. No initializer calls `dataset_db`, so the parent process does not open a dataset.

Probe scripts ran against libduckdb 1.5.6 and the `duckdb` gem 2.0.0.1:

```
1. insert error: Sequel::DatabaseError: DuckDB::Error: Invalid Input Error: Cannot execute statement of type "INSERT" on database "dataset" which is attached in read-only mode!
2. second conn count: 2  pool size: 2
3. after CREATE patients, db[:patients].count = 0 (dataset has 2)
4. other thread sees scratch: true
5. distinct connections for same file: 3
6. typo file: Sequelizer::MissingDatasetError: /tmp/d20261030-4122931-fztfuu/synpuf/gdmm.duckdb/synpuf must hold exactly one *.duckdb file to be the dataset synpuf, but it holds 0
before replace: 2
after replace + disconnect: 2  (new file has 5)
child same object: true count: 1     (fork after parent opened and disconnected)
```

## The six findings

1. **The cache key is the URL text, not the file.** `duckdb:///d`, `duckdb:///d/` and the file's own URL opened three in-memory DuckDB databases on one file. Each gets its own memory_limit, and the settings conflict check does not compare them.
2. **A cached connection never sees a replaced dataset file.** After the file was replaced and `db.disconnect` ran, the count stayed 2 (the new file has 5). The in-memory database never closes, and `ATTACH IF NOT EXISTS` skips. No API drops a cache entry, so a consumer test suite also cannot reset the cache.
3. **A table created without a catalog hides the dataset table of the same name**, for every thread in the process, because `memory.main` is first on the search path and the connection is shared.
4. **`test_a_write_to_the_dataset_fails` accepts any `Sequel::DatabaseError`**, so a missing-table error would pass too.
5. **A file URL with a typo is treated as a directory**, and the error names `<file>/<schema>`, which misleads.
6. **`bin/install-libduckdb` does not verify a checksum** of the DuckDB library it downloads. sequel-duckdb's copy has the same gap.

## Options for item 3

A DuckDB probe tested the dataset first on the search path (`dataset.s,memory.main`):

```
A dataset-first: SELECT p: [[2]]
A CREATE x unqualified: ERR Invalid Input Error: Cannot execute statement of type "CREATE" on database "dataset" which is attached in read-only mode!
A CREATE memory.main.p: [[2]]
B USE memory.main then path: ERR ... (USE does not change where CREATE goes; the first search path entry decides)
```

- (a) Dataset first. Reads always reach the dataset, and an unqualified CREATE fails. It changes published behavior, so the next release would be 0.5.0.
- (b) Keep `memory.main` first, and document the hiding behavior.

## Options for item 2

- (a) Auto-reopen: each call checks the file's identity and opens a new connection when the file changed, plus a close API.
- (b) A close API only.

## Rulings (2026-10-30)

- Item 3: Ryan chose "Keep order, document".
- Item 2: Ryan asked "which is the more explicit and least surprising?". The agent answered that the close API only is both. The connection changes only when code asks, and it reads the file that existed at the first call. Auto-reopen changes the connection without being asked, and during a swap it holds two DuckDB databases in one process, each with its own memory_limit. So item 2 is (b), and the docs state the rule.
- Item 1: key the cache on the real path of the resolved dataset file and the schema.
- Item 5: a URL whose path is neither a file nor a directory raises `MissingDatasetError` with a message that says so. jigsaw-diagram-editor rescues that class, so the class stays.
- Item 6: pin the SHA-256 of each libduckdb asset in this repo and verify it. The copy in sequel-duckdb is not changed from here.
- All six: Ryan said "seed and bead and fix all 6 please".

UPDATE 2026-10-30: all six are fixed on main at merge 1e6e053, which is not released and not pushed. just ci passes, and 248 tests pass on Ruby 3.3, 3.4 and 4.0.

- sequelizer-ttu (5182707): a URL path that is neither a file nor a directory raises MissingDatasetError with its own message.
- sequelizer-m9c (50f6242): the cache key is the real path of the resolved dataset file and the schema.
- sequelizer-f7a (a309e22): Sequelizer.close_dataset_dbs detaches, disconnects and empties the cache, and keep_reference: false lets a dropped connection be freed. A probe showed one open file handle on the dataset before the call and none after it.
- sequelizer-asi (3901a13): the README and YARD docs state the hiding behavior, and a test records it.
- sequelizer-n5w (2a7b6e8): the write test matches DuckDB's read-only message.
- sequelizer-dj4 (92a663d): bin/install-libduckdb pins the SHA-256 of 1.5.6 (b845005f...841b, GitHub's digest, confirmed by a download) and stops on a mismatch or an unpinned version.

Not done here: sequel-duckdb's copy of bin/install-libduckdb still has no checksum check.
