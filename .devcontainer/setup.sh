#!/bin/bash
set -e

# Update system packages
sudo apt-get update
sudo apt-get install -y build-essential git curl libssl-dev libreadline-dev zlib1g-dev \
    libncurses5-dev libncursesw5-dev libsqlite3-dev xz-utils tk-dev libxml2-dev \
    libxmlsec1-dev libffi-dev liblzma-dev

# Install PostgreSQL client for database connectivity
sudo apt-get install -y postgresql-client

# Set up Ruby environment
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc

# Install bundler
gem install bundler

# Install project dependencies
bundle install

# Install overcommit hooks
bundle exec overcommit --install
bundle exec overcommit --sign

# Set up git configuration for the container
git config --global --add safe.directory /workspaces/sequelizer

echo "✅ Development environment setup complete!"
echo "🚀 You can now run:"
echo "   bundle exec rake test    # Run tests"
echo "   bundle exec rake lint    # Run linting"
echo "   bundle exec rake coverage # Run coverage report"