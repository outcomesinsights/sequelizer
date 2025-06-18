# Use the official Microsoft Ruby devcontainer as base
FROM mcr.microsoft.com/devcontainers/ruby:1-3.3-bullseye

# Install additional packages needed for Ruby gem development
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        build-essential \
        git \
        curl \
        libssl-dev \
        libreadline-dev \
        zlib1g-dev \
        libncurses5-dev \
        libncursesw5-dev \
        libsqlite3-dev \
        xz-utils \
        tk-dev \
        libxml2-dev \
        libxmlsec1-dev \
        libffi-dev \
        liblzma-dev \
        postgresql-client \
        sqlite3 \
    && apt-get autoremove -y && apt-get clean -y

# Install latest bundler
RUN gem install bundler

# Set up working directory
WORKDIR /workspaces/sequelizer

# Copy gem files for dependency installation
COPY Gemfile* ./
COPY sequelizer.gemspec ./
COPY lib/sequelizer/version.rb ./lib/sequelizer/

# Install dependencies
RUN bundle install

# Set up git safe directory
RUN git config --global --add safe.directory /workspaces/sequelizer