# frozen_string_literal: true

require "test_helper"

class CoreTest < BrieflyTest
  def test_new_returns_independent_facades
    a = Briefly.new { shortcut(:only_a) { 1 } }
    b = Briefly.new { shortcut(:only_b) { 2 } }

    refute_same a, b
    refute a.shortcut?(:only_b)
    refute b.shortcut?(:only_a)
  end

  def test_empty_facade_is_valid
    facade = Briefly.new

    assert_empty facade.shortcuts
    refute facade.shortcut?(:anything)
  end

  def test_shortcuts_are_sorted_canonical_names_only
    facade = Briefly.new do
      shortcut(:zeta) { 1 }
      shortcut(:alpha, :a) { 2 }
    end

    assert_equal %i[alpha zeta], facade.shortcuts
  end

  def test_shortcut_predicate_accepts_canonical_and_alias
    facade = Briefly.new { shortcut(:config, :c) { 1 } }

    assert facade.shortcut?(:config)
    assert facade.shortcut?(:c)
    refute facade.shortcut?(:nope)
  end

  def test_configure_adds_shortcuts_to_an_existing_facade
    facade = Briefly.new
    facade.configure { shortcut(:late) { :added } }

    assert_equal :added, facade.late
  end

  def test_configure_returns_the_facade
    facade = Briefly.new

    result = facade.configure { shortcut(:x) { 1 } }

    assert_same facade, result
  end

  def test_configure_preserves_existing_definitions_and_memoization
    calls = 0
    facade = Briefly.new do
      shortcut(:cached) { calls += 1 }
      memoize :cached
    end
    facade.configure { shortcut(:other) { :other } }

    facade.cached
    facade.cached

    assert_equal 1, calls
    assert_equal %i[cached other], facade.shortcuts
  end

  def test_configure_can_memoize_a_previously_declared_shortcut
    calls = 0
    facade = Briefly.new { shortcut(:cached) { calls += 1 } }
    facade.configure { memoize :cached }

    facade.cached
    facade.cached

    assert_equal 1, calls
  end

  def test_configure_preserves_previously_registered_handlers
    facade = Briefly.new do
      shortcut(:boom) { raise "kaboom" }
      rescue_from(RuntimeError, :boom) { :rescued }
    end
    facade.configure { shortcut(:other) { :other } }

    assert_equal :rescued, facade.boom
  end

  # A builder pass that raises in compile! must leave the live facade exactly as it was.
  def test_a_raising_configure_does_not_memoize_the_facade
    calls = 0
    facade = Briefly.new { shortcut(:value) { calls += 1 } }

    assert_raises(Briefly::Error) do
      facade.configure do
        memoize :value
        shortcut(:bad) { |arg| arg }
        memoize :bad
      end
    end

    3.times { facade.value }

    assert_equal 3, calls
    refute facade.shortcut?(:bad)
  end

  def test_a_raising_configure_does_not_steal_an_alias
    facade = Briefly.new { shortcut(:config, :c) { :value } }

    assert_raises(Briefly::Error) do
      facade.configure do
        shortcut(:other, :c) { :stolen }
        shortcut(:bad) { |arg| arg }
        memoize :bad
      end
    end
    facade.configure { shortcut(:unrelated) { :u } }

    assert facade.shortcut?(:c)
    assert_equal :value, facade.c
  end

  def test_inspect_lists_shortcut_names_and_hides_memo_internals
    facade = Briefly.new do
      shortcut(:secret) { "s3cr3t" }
      memoize :secret
    end
    facade.secret

    assert_equal "#<Briefly::Facade shortcuts=[:secret]>", facade.inspect
    assert_equal facade.inspect, facade.to_s
    refute_includes facade.inspect, "s3cr3t"
  end
end
