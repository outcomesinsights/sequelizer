require 'thor'
require 'pp'
require_relative 'gemfile_modifier'

module Sequelizer
  class CLI < Thor

    desc 'update_gemfile',
         'adds or replaces a line in your Gemfile to include the correct database adapter to work with Sequel'
    option 'dry-run', type: :boolean, desc: 'Only prints out what it would do, but makes no changes'
    option 'skip-bundle', type: :boolean, desc: "Don't run `bundle install` after modifying Gemfile"
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
