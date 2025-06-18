require_relative 'options'

module Sequelizer
  class GemfileModifier

    attr_reader :options

    def initialize(options = {})
      @options = options
    end

    def modify
      check_for_gemfile
      if gemfile_needs_modification?
        modify_gemfile
        run_bundle unless options['skip-bundle']
      else
        puts 'Gemfile needs no modification'
      end
    end

    private

    def modify_gemfile
      puts %(Adding "#{gem_line}" to Gemfile)
      return if options['dry-run']

      File.write(gemfile, modified_lines.join("\n"))
    end

    def proper_gem
      opts = Options.new
      @proper_gem ||= case opts.adapter
                      when 'postgres'
                        'pg'
                      when 'sqlite'
                        'sqlite3'
                      when 'mysql'
                        'mysql2'
                      when 'tinytds'
                        'tiny_tds'
                      when 'oracle'
                        'ruby-oci8'
                      when nil
                        raise 'No database adapter defined in your Sequelizer configuration'
                      else
                        raise "Don't know which database gem to use with adapter: #{opts.adapter}"
                      end
    end

    def gem_line
      "gem '#{proper_gem}'"
    end

    def gem_line_comment
      '# ADDED BY SEQUELIZER'
    end

    def full_gem_line
      [gem_line, gem_line_comment].join(' ')
    end

    def gemfile_needs_modification?
      !(gemfile_lines.include?(gem_line) || gemfile_lines.include?(full_gem_line))
    end

    def gemfile_lines
      @gemfile_lines ||= File.readlines(gemfile).map(&:chomp)
    end

    def modified_lines
      gemfile_lines.grep_v(Regexp.new(gem_line_comment)) + [full_gem_line]
    end

    def check_for_gemfile
      return if gemfile.exist?

      raise "Could not find Gemfile in current directory: #{Pathname.pwd}"
    end

    def run_bundle
      puts 'Running `bundle install` to update dependencies'
      system('bundle install')
    end

    def gemfile
      @gemfile ||= Pathname.new('Gemfile')
    end

  end
end
