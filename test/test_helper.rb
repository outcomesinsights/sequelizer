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
