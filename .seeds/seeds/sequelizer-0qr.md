---
id: sequelizer-0qr
title: Spin off each Sequel extension into its own gem?
status: captured
type: question
created_at: 2026-10-14T13:51:16.834225+00:00
updated_at: 2026-10-14T13:51:16.834225+00:00
tags:
  - extensions
  - packaging
---

## Question

Ryan asked on 2026-10-14: "should we spin off each extension into its own gem?"

## Facts at the time of the question (2026-10-14)

The gem ships 11 Sequel extensions in `lib/sequel/extensions/`: cold_col, db_opts, funky, make_readyable, more_sql, platform, settable, smart_select_remove, sql_recorder, unionize and usable.

Runtime dependencies are dotenv, kvcsv, sequel and thor. Of these, only kvcsv belongs to an extension (platform). dotenv and thor belong to the connection and CLI side.

Coupling that already exists between the parts:

- `lib/sequelizer.rb` requires settable directly.
- db_opts loads settable and calls its private `set_sql`.
- ConnectionMaker applies db_opts to every new connection.
- platform reads `config/platforms/*.csv` from the installed gem directory.

Consumers, from the 2026-10-07 audit (sequelizer-i33): summarb, t_shank, roobetl and conceptql each load one or more of usable, more_sql, unionize, settable, cold_col, smart_select_remove, make_readyable and funky. No OI repo outside this gem loads platform or sql_recorder.

Open beads plan to move more extensions INTO this gem from summarb, conceptql and roobetl (the consolidation beads, and sequelizer-b6t for funky and platform). A split runs in the opposite direction, so the answer here affects those beads.

## Not yet deliberated

Options include one gem per extension, one gem for all extensions separate from the connection code, or no split. Each split adds a gem to release through the tag-gated release workflow, and adds dependency lines to every consumer.
