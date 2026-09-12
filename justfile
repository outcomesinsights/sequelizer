# Run the full test suite (matches CI)
test:
    bundle exec rubocop
    bundle exec rake test

bundle-update *ARGS:
    bundle update {{ ARGS }}

# Re-pin this gem's OI git deps to their current main HEAD (lock-only; review the diff).
# Part of the ordered cascade — see the jigsaw habitat's gem-dependency-order note.
bump-oi:
    bundle lock --update sequel-duckdb sequel-hexspace
    @git --no-pager diff --stat -- Gemfile.lock

# Rewrite files to canonical format. Run deliberately; never from a hook.
fmt:
    git ls-files "*.sh" | xargs -r shfmt -w
    just --fmt --unstable
    git ls-files "*.md" | xargs -r mdformat

# Report format drift without changing anything. This is what the hooks run —
# a formatter that rewrites files mid-commit changes what you already reviewed.
fmt-check:
    git ls-files "*.sh" | xargs -r shfmt -d
    just --fmt --check --unstable
    git ls-files "*.md" | xargs -r mdformat --check

# Full local CI equivalent — run this before pushing.
# The recipe IS the contract: if CI runs a check and this does not, the gate is
# decorative (see ~/.config/home-manager/docs/ci-gates.md).
ci: fmt-check test

# What actually runs before a push. Defaults to the complete `ci`; point it at
# something smaller ONLY where running complete CI locally is impractical.
pre-push: ci

# Runs on every commit, so it must stay FAST — a sub-minute budget. Tests belong
# here when they fit; lint alone when they do not. fmt-check never rewrites.
pre-commit: fmt-check test
