# frozen_string_literal: true

require "test_helper"
require "support/rails_double"

class RailsReloadTest < BrieflyTest
  def test_a_standalone_facade_clears_its_memos_on_prepare
    RailsDouble.with(root: Dir.pwd) do |rails, _controller|
      calls = 0
      facade = Briefly.define do
        use Briefly::Rails::Reload
        shortcut(:value) { calls += 1 }
        memoize :value
      end

      facade.value
      facade.value

      assert_equal 1, calls

      rails.application.reloader.prepare!
      facade.value

      assert_equal 2, calls
    end
  end

  def test_the_reload_pack_adds_no_shortcuts
    RailsDouble.with(root: Dir.pwd) do
      facade = Briefly.define { use Briefly::Rails::Reload }

      assert_empty facade.briefly.shortcuts
    end
  end

  # The pack memoizes nothing itself, but it composes Reload so the app's own memos clear.
  def test_the_rails_pack_composes_the_reload_pack
    RailsDouble.with(root: Dir.pwd) do |rails, _controller|
      calls = 0
      facade = Briefly.define do
        use Briefly::Rails
        shortcut(:policy) { calls += 1 }
        memoize :policy
      end
      facade.policy
      facade.policy

      assert_equal 1, calls

      rails.application.reloader.prepare!

      assert_equal 0, memo_count(facade)

      facade.policy

      assert_equal 2, calls
    end
  end

  def test_reconfiguring_does_not_register_a_duplicate_callback
    RailsDouble.with(root: Dir.pwd) do |rails, _controller|
      cleared = 0
      facade = Briefly.define { use Briefly::Rails::Reload }
      facade.briefly.configure { use Briefly::Rails::Reload }
      facade.define_singleton_method(:__clear_memos!) { cleared += 1 }

      rails.application.reloader.prepare!

      assert_equal 1, cleared
    end
  end

  def test_it_raises_outside_a_booted_application
    error = assert_raises(Briefly::Error) { Briefly.define { use Briefly::Rails::Reload } }

    assert_match(/booted application/, error.message)
  end

  private

  def memo_count(facade)
    facade.instance_variable_get(:@__memos).size
  end
end
