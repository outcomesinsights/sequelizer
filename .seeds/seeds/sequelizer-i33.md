---
id: sequelizer-i33
title: 'Over-engineering audit 2026-10-07: accept findings 2, 4-8; keep platform and sql_recorder'
status: resolved
type: decision
created_at: 2026-10-07T17:46:53.568935+00:00
updated_at: 2026-10-14T14:01:47.756940+00:00
resolved_at: 2026-10-14T13:59:13.981462+00:00
resolution: "All six accepted findings shipped on 2026-10-07 (merges 42ea95b, 1b9bf3a, 7bf5115 and 9439329), as the seed's OUTCOME and UPDATE notes record. The two rejected findings (the platform extension and sql_recorder) stay by ruling. Efficacy: tweaking needed: minor. Two findings changed during implementation. Finding 5 moved from the planned test:false approach to :before_preconnect, because test:false broke preconnect (an inherent unknown). Finding 6 needed a second ruling on symbol keys, because the audit missed that the gem's own test asserts indifferent access (a planning miss: a better bead would have grepped the tests for both h[:k] and h['k'])."
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

OUTCOME (2026-10-07, /bead-go run, merged to local main 7bf5115, not pushed): 5 of 6 accepted findings implemented. 5 -> sequelizer-2z1 (monkey patch removed; db_opts now via Sequel's public :before_preconnect, because the planned test:false approach broke preconnect) + 8 -> sequelizer-wr7, merged 42ea95b. 4 -> sequelizer-ajb (breaking: update_gemfile removed) + 7 -> sequelizer-zc8 (pp dropped), merged 1b9bf3a. 2 -> sequelizer-9ce (activesupport dropped from runtime deps; it stays in Gemfile.lock only via the rubocop-rails dev dependency), merged 7bf5115. NOT DONE: 6 -> sequelizer-9b2 (hashie) bailed: plain hashes cannot keep Sequelizer.options' indifferent access (both h[:k] and h["k"] work today, asserted by the gem's own test); needs a ruling between symbol keys, string keys, HashWithIndifferentAccess (conflicts with 2) and a custom class. Side effect of 5: Sequelizer.options no longer contains an injected Proc, so it is empty with no config (t_shank's spec_helper .empty? guard is now live).

UPDATE 2026-10-07: 6 -> sequelizer-9b2 done after Ryan ruled option (a), symbol keys: hashie and OptionsHash removed, Sequelizer.options/Options#to_hash return a plain symbol-keyed Hash (keys symbolized at every depth), committed as breaking (refactor!, 490c924), merged 9439329. All six accepted findings are now implemented; runtime deps are dotenv, kvcsv, sequel, thor. Side effect: a servers: override (e.g. a read_only host) now applies instead of being silently ignored; no OI repo configures Sequel servers:.

UPDATE 2026-10-14: verified against the working tree at a46403e before this resolution was confirmed. The resolution itself was written from this seed's notes, so this note records the code check.

- Finding 2: `sequelizer.gemspec` has no activesupport line, and `lib/sequel/extensions/cold_col.rb` has no `blank?`, `present?`, `try(` or `active_support`. Commit 3380d25.
- Finding 4: `lib/sequelizer/gemfile_modifier.rb` and its test are gone, and nothing in `lib/` names `update_gemfile`. Commit 4837ff4.
- Finding 5: `lib/sequelizer/monkey_patches/` is gone. `lib/sequelizer/connection_maker.rb:73-78` applies db_opts through `:before_preconnect`. Commit 3507790.
- Finding 6: there is no hashie in the gemspec or Gemfile, and `lib/sequelizer/options_hash.rb` is gone. Nothing in `lib/` or `test/` names `OptionsHash` or `Hashie`. Commit 490c924.
- Finding 7: there is no `pp` dependency in the gemspec and no `require "pp"` in `lib/sequelizer/cli.rb`. Commit 8f186b3.
- Finding 8: nothing in `lib/` names `configure_adapter_specific_options`. Commit 33da14e.
- The rejected findings stay: `lib/sequel/extensions/platform.rb`, `lib/sequel/extensions/sql_recorder.rb` and the kvcsv dependency are present.
