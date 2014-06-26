require 'thor'
require_relative 'gemfile_modifier'

module Sequelizer
  class CLI < Thor
    desc 'update_gemfile', 'adds or replaces a line in your Gemfile to include the correct database adapter to work with Sequel'
    option 'dry-run', type: :boolean, desc: 'Only prints out what it would do, but makes no changes'
    option 'skip-bundle', type: :boolean, desc: "Don't run `bundle install` after modifying Gemfile"
    def update_gemfile
      GemfileModifier.new(options).modify
    end
  end
end
