# Run the full test suite (matches CI)
test:
    bundle exec rubocop
    bundle exec rake test

bundle-update *ARGS:
    bundle update {{ARGS}}
