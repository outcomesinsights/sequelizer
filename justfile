# Run the full test suite (matches CI)
test:
    bundle exec rubocop
    bundle exec rake test

bundle-update *ARGS:
    bundle update {{ARGS}}

# Re-pin this gem's OI git deps to their current main HEAD (lock-only; review the diff).
# Part of the ordered cascade — see the jigsaw habitat's gem-dependency-order note.
bump-oi:
    bundle lock --update sequel-duckdb sequel-hexspace
    @git --no-pager diff --stat -- Gemfile.lock
