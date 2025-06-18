require 'thor'
require 'pp'
require_relative 'gemfile_modifier'

module Sequelizer
  # = CLI
  #
  # Command line interface for Sequelizer gem using Thor.
  # Provides commands for:
  #
  # * Updating Gemfile with database adapters
  # * Initializing .env files with database configuration
  # * Displaying current configuration
  #
  # @example
  #   sequelizer update_gemfile
  #   sequelizer init_env --adapter postgres --host localhost
  #   sequelizer config
  class CLI < Thor

    desc 'update_gemfile',
         'adds or replaces a line in your Gemfile to include the correct database adapter to work with Sequel'
    option 'dry-run', type: :boolean, desc: 'Only prints out what it would do, but makes no changes'
    option 'skip-bundle', type: :boolean, desc: "Don't run `bundle install` after modifying Gemfile"
    # Updates the Gemfile to include the appropriate database adapter gem.
    #
    # This command analyzes your current database configuration and adds or updates
    # the corresponding database adapter gem in your Gemfile. It supports various
    # adapters including PostgreSQL, MySQL, SQLite, and JDBC-based adapters.
    #
    # @option options [Boolean] dry-run Only prints what would be done without making changes
    # @option options [Boolean] skip-bundle Skip running `bundle install` after modification
    def update_gemfile
      GemfileModifier.new(options).modify
    end

    desc 'init_env', 'creates a .env file with the parameters listed'
    option :adapter,
           aliases: :a,
           desc: 'adapter for database'
    option :host,
           aliases: :h,
           banner: 'localhost',
           desc: 'host for database'
    option :username,
           aliases: :u,
           desc: 'username for database'
    option :password,
           aliases: :P,
           desc: 'password for database'
    option :port,
           aliases: :p,
           type: :numeric,
           banner: '5432',
           desc: 'port for database'
    option :database,
           aliases: :d,
           desc: 'database for database'
    option :search_path,
           aliases: :s,
           desc: 'schema for database (PostgreSQL only)'
    # Creates a .env file with database configuration parameters.
    #
    # This command generates a .env file with SEQUELIZER_* environment variables
    # based on the provided options. It will not overwrite an existing .env file.
    #
    # @option options [String] :adapter Database adapter (e.g., 'postgres', 'mysql2')
    # @option options [String] :host Database host (default: 'localhost')
    # @option options [String] :username Database username
    # @option options [String] :password Database password
    # @option options [Integer] :port Database port (default: 5432 for PostgreSQL)
    # @option options [String] :database Database name
    # @option options [String] :search_path PostgreSQL schema search path
    # @raise [SystemExit] if .env file already exists
    def init_env
      if File.exist?('.env')
        puts ".env already exists!  I'm too cowardly to overwrite it!"
        puts "Here's what I would have put in there:"
        puts make_env(options)
        exit(1)
      end
      File.open('.env', 'w') do |file|
        file.puts make_env(options)
      end
    end

    desc 'config', 'prints out the connection parameters'
    # Displays the current database configuration and extensions.
    #
    # This command shows the resolved configuration options that would be used
    # for database connections, including all merged sources and any Sequel
    # extensions that would be loaded.
    def config
      opts = Options.new
      pp opts.to_hash
      pp opts.extensions
    end

    private

    def make_env(options)
      options.map do |key, value|
        "SEQUELIZER_#{key.upcase}=#{value}"
      end.join("\n")
    end

  end
end
