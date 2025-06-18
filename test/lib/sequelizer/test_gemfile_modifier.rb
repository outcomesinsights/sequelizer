require_relative '../../test_helper'
require 'sequelizer/gemfile_modifier'

class TestGemfileModifier < Minitest::Test

  def setup
    @gm = Sequelizer::GemfileModifier.new
  end

  def test_dies_if_Gemfile_missing
    pn_mock = Minitest::Mock.new
    pn_mock.expect(:exist?, false)

    Pathname.stub(:new, pn_mock) do
      assert_raises(RuntimeError) { @gm.modify }
    end
    pn_mock.verify
  end

  def test_quits_if_no_modification_needed
    opts_mock = Minitest::Mock.new
    pn_mock = standard_pn_mock
    opts_mock.expect(:adapter, 'postgres')
    file_mock = Minitest::Mock.new
    file_mock.expect(:readlines, ["gem 'pg'"], [pn_mock])

    Pathname.stub(:new, pn_mock) do
      Sequelizer::Options.stub(:new, opts_mock) do
        stub_const(Sequelizer::GemfileModifier, :File, file_mock) do
          stub_modifying_methods(@gm) do
            @gm.modify
          end
        end
      end
    end
  end

  def test_quits_if_no_modification_needed2
    opts_mock = Minitest::Mock.new
    pn_mock = standard_pn_mock
    opts_mock.expect(:adapter, 'postgres')
    file_mock = Minitest::Mock.new
    file_mock.expect(:readlines, ["gem 'pg' # ADDED BY SEQUELIZER"], [pn_mock])

    Pathname.stub(:new, pn_mock) do
      Sequelizer::Options.stub(:new, opts_mock) do
        stub_const(Sequelizer::GemfileModifier, :File, file_mock) do
          stub_modifying_methods(@gm) do
            @gm.modify
          end
        end
      end
    end
  end

  def test_writes_if_modification_needed
    opts_mock = Minitest::Mock.new
    pn_mock = standard_pn_mock
    opts_mock.expect(:adapter, 'postgres')
    file_mock = Minitest::Mock.new
    file_mock.expect(:readlines, ['#comment line', "gem 'sqlite3' # ADDED BY SEQUELIZER"], [pn_mock])
    file_mock.expect(:write, nil, [pn_mock, ['#comment line', "gem 'pg' # ADDED BY SEQUELIZER"].join("\n")])

    Pathname.stub(:new, pn_mock) do
      Sequelizer::Options.stub(:new, opts_mock) do
        stub_const(Sequelizer::GemfileModifier, :File, file_mock) do
          stub_modifying_methods(@gm) do
            @gm.modify
          end
        end
      end
    end
  end

  private

  def standard_pn_mock
    pn_mock = Minitest::Mock.new
    pn_mock.expect(:exist?, true)
  end

  def stub_modifying_methods(obj, &block)
    obj.stub(:system, nil) do
      obj.stub(:puts, nil, &block)
    end
  end

end
