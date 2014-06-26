require 'minitest/autorun'

class Minitest::Test
  def stub_const(klass, const, replace, &block)
    klass.send(:const_set, const, replace)
    if block_given?
      yield
      remove_stubbed_const(klass, const)
    end
  end

  def remove_stubbed_const(klass, const)
    klass.send(:remove_const, const)
  end
end
