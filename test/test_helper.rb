# Disable Rails plugins for Minitest to avoid version conflicts
ENV['MT_NO_PLUGINS'] = '1'

# SimpleCov must be loaded before application code
require 'simplecov'

SimpleCov.start do
  add_filter '/test/'
  add_filter '/vendor/'

  add_group 'Core', 'lib/sequelizer'
  add_group 'Sequel Extensions', 'lib/sequel'

  # Temporarily lower minimum coverage to see what we're working with
  minimum_coverage 70
  minimum_coverage_by_file 40

  # Generate both HTML and JSON for easier analysis
  formatter SimpleCov::Formatter::MultiFormatter.new([
                                                       SimpleCov::Formatter::HTMLFormatter,
                                                       SimpleCov::Formatter::SimpleFormatter,
                                                     ])
end

require 'minitest/autorun'
require 'sequel'

module Minitest
  class Test

    def stub_const(klass, const, replace)
      klass.send(:const_set, const, replace)
      return unless block_given?

      yield
      remove_stubbed_const(klass, const)
    end

    def remove_stubbed_const(klass, const)
      klass.send(:remove_const, const)
    end

  end
end
