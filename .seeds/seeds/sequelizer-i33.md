---
id: sequelizer-i33
title: 'Over-engineering audit 2026-10-07: accept findings 2, 4-8; keep platform and sql_recorder'
status: captured
type: decision
created_at: 2026-10-07T17:46:53.568935+00:00
updated_at: 2026-10-07T17:46:53.568935+00:00
tags:
  - audit
  - dependencies
  - simplification
---

Over-engineering audit of the whole tree (/ponytail-audit, 2026-10-07), and Ryan's ruling on it.

RULING (Ryan, 2026-10-07): "I accept all except 1, 3". Accepted: 2, 4, 5, 6, 7, 8. Rejected: 1 and 3.

Findings, as ranked in the audit (every delete was grep-checked across all outins repos, excluding vendored copies):

1. REJECTED. yagni: the platform extension + kvcsv dependency + config/platforms/\*.csv. No OI repo loads it; it exists for the planned Platform abstraction (bead b6t and the consolidation beads). Stays because that plan stands.
2. ACCEPTED. stdlib: drop the activesupport runtime dependency (12 transitive gems, including minitest at runtime) for three calls in lib/sequel/extensions/cold_col.rb: blank?, present?, .try(:alias). Verified 2026-10-07: every OI consumer that uses ActiveSupport (conceptql, t_shank, jigsaw-diagram-editor, roobetl) declares it itself; summarb does not use it.
3. REJECTED. delete: the sql_recorder extension. No OI repo outside this gem loads it, but it is published API; kept.
4. ACCEPTED. yagni: the `update_gemfile` CLI command and Sequelizer::GemfileModifier (lib/sequelizer/gemfile_modifier.rb + its test). No repo or script calls it. Replacement: `bundle add <adapter gem>`. Removing a CLI command is breaking for its users: commit as breaking (0.x minor bump).
5. ACCEPTED. native: remove the ConnectionPool#make_new monkey patch (lib/sequelizer/monkey_patches/database_in_after_connect.rb), which redefines a private Sequel method and warns "method redefined" on every load. It exists only so make_ac receives db for db_opts. Replacement: in ConnectionMaker connect with test: false, give the after_connect proc the db through a captured variable, then db.test_connection (Sequel public API; its 2-arity after_connect suffices). Sequel's ConnectionPool#after_connect= is marked SEQUEL6: Remove, so not that.
6. ACCEPTED. stdlib: drop the hashie dependency; Sequelizer::OptionsHash (7 lines) only provides indifferent access. Replacement: symbolize keys at the option sources (transform_keys(&:to_sym)); also retires the merge! workaround comment in Options#fix_options. No OI repo uses OptionsHash or Hashie.
7. ACCEPTED. native: drop the `pp` dependency and `require "pp"` in cli.rb. pp is a default gem on Ruby 3.3/3.4/4.0 (measured: activates with no Gemfile entry) and Kernel#pp needs no require.
8. ACCEPTED. delete: ConnectionMaker#configure_adapter_specific_options, an empty method ("No adapter-specific configuration needed currently") with one caller.

Kept after checking: Sequelizer.options (t_shank and jigsaw-diagram-editor call it); usable, more_sql, unionize, settable, cold_col, smart_select_remove, make_readyable, funky (each loaded by summarb, t_shank, roobetl or conceptql); db_opts (internal); the db/new_db double cache (removing it changes behaviour).
