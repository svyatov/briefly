# frozen_string_literal: true

require "test_helper"

class CoreTest < BrieflyTest
  # +Briefly+ is a module, so it inherits no +new+ from +Module+: removing the method is the whole
  # deprecation. There is no silent-wrong-behavior path left behind. This is the only +Briefly.new+
  # left in the tree, and it is here to prove there is nothing behind it.
  def test_the_old_new_entry_point_no_longer_exists
    refute_respond_to Briefly, :new
    assert_raises(NoMethodError) { Briefly.new { shortcut(:x) { 1 } } }
  end

  def test_define_returns_independent_facades
    a = Briefly.define { shortcut(:only_a) { 1 } }
    b = Briefly.define { shortcut(:only_b) { 2 } }

    refute_same a, b
    refute a.briefly.shortcut?(:only_b)
    refute b.briefly.shortcut?(:only_a)
  end

  def test_empty_facade_is_valid
    facade = Briefly.define

    assert_empty facade.briefly.shortcuts
    refute facade.briefly.shortcut?(:anything)
  end

  def test_shortcuts_are_sorted_canonical_names_only
    facade = Briefly.define do
      shortcut(:zeta) { 1 }
      shortcut(:alpha, :a) { 2 }
    end

    assert_equal %i[alpha zeta], facade.briefly.shortcuts
  end

  def test_shortcut_predicate_accepts_canonical_and_alias
    facade = Briefly.define { shortcut(:config, :c) { 1 } }

    assert facade.briefly.shortcut?(:config)
    assert facade.briefly.shortcut?(:c)
    refute facade.briefly.shortcut?(:nope)
  end

  def test_configure_adds_shortcuts_to_an_existing_facade
    facade = Briefly.define
    facade.briefly.configure { shortcut(:late) { :added } }

    assert_equal :added, facade.late
  end

  def test_configure_returns_the_facade
    facade = Briefly.define

    result = facade.briefly.configure { shortcut(:x) { 1 } }

    assert_same facade, result
  end

  def test_configure_preserves_existing_definitions_and_memoization
    calls = 0
    facade = Briefly.define do
      shortcut(:cached) { calls += 1 }
      memoize :cached
    end
    facade.briefly.configure { shortcut(:other) { :other } }

    facade.cached
    facade.cached

    assert_equal 1, calls
    assert_equal %i[cached other], facade.briefly.shortcuts
  end

  def test_configure_can_memoize_a_previously_declared_shortcut
    calls = 0
    facade = Briefly.define { shortcut(:cached) { calls += 1 } }
    facade.briefly.configure { memoize :cached }

    facade.cached
    facade.cached

    assert_equal 1, calls
  end

  def test_configure_preserves_previously_registered_handlers
    facade = Briefly.define do
      shortcut(:boom) { raise "kaboom" }
      rescue_from(RuntimeError, :boom) { :rescued }
    end
    facade.briefly.configure { shortcut(:other) { :other } }

    assert_equal :rescued, facade.boom
  end

  # A builder pass that raises in compile! must leave the live facade exactly as it was.
  def test_a_raising_configure_does_not_memoize_the_facade
    calls = 0
    facade = Briefly.define { shortcut(:value) { calls += 1 } }

    assert_raises(Briefly::Error) do
      facade.briefly.configure do
        memoize :value
        shortcut(:bad) { |arg| arg }
        memoize :bad
      end
    end

    3.times { facade.value }

    assert_equal 3, calls
    refute facade.briefly.shortcut?(:bad)
  end

  def test_a_raising_configure_does_not_steal_an_alias
    facade = Briefly.define { shortcut(:config, :c) { :value } }

    assert_raises(Briefly::Error) do
      facade.briefly.configure do
        shortcut(:other, :c) { :stolen }
        shortcut(:bad) { |arg| arg }
        memoize :bad
      end
    end
    facade.briefly.configure { shortcut(:unrelated) { :u } }

    assert facade.briefly.shortcut?(:c)
    assert_equal :value, facade.c
  end

  def test_inspect_lists_shortcut_names_and_hides_memo_internals
    facade = Briefly.define do
      shortcut(:secret) { "s3cr3t" }
      memoize :secret
    end
    facade.secret

    assert_equal "#<Briefly::Facade shortcuts=[:secret]>", facade.inspect
    assert_equal facade.inspect, facade.to_s
    refute_includes facade.inspect, "s3cr3t"
  end
end
