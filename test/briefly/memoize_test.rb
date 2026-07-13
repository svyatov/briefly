# frozen_string_literal: true

require "test_helper"

class MemoizeTest < BrieflyTest
  def test_body_runs_once
    calls = 0
    facade = Briefly.define do
      shortcut(:value) { calls += 1 }
      memoize :value
    end

    3.times { facade.value }

    assert_equal 1, calls
  end

  def test_memoizes_nil
    calls = 0
    facade = Briefly.define do
      shortcut(:nothing) do
        calls += 1
        nil
      end
      memoize :nothing
    end

    assert_nil facade.nothing
    assert_nil facade.nothing
    assert_equal 1, calls
  end

  def test_memoizes_false
    facade = Briefly.define do
      shortcut(:no) { false }
      memoize :no
    end

    refute facade.no
    refute facade.no
  end

  def test_aliases_share_one_memo_cell
    calls = 0
    facade = Briefly.define do
      shortcut(:value, :v) { calls += 1 }
      memoize :value
    end

    facade.value
    facade.v

    assert_equal 1, calls
  end

  def test_memoize_accepts_an_alias
    calls = 0
    facade = Briefly.define do
      shortcut(:value, :v) { calls += 1 }
      memoize :v
    end

    facade.value
    facade.value

    assert_equal 1, calls
  end

  def test_memoize_returns_the_canonical_name
    name = nil
    Briefly.define do
      shortcut(:value, :v) { 1 }
      name = memoize(:v)
    end

    assert_equal :value, name
  end

  # A transient failure must be retried on the next access, never pinned.
  def test_a_rescued_fallback_is_not_memoized
    calls = 0
    facade = Briefly.define do
      shortcut(:flaky) do
        calls += 1
        raise "transient" if calls == 1

        :ok
      end
      memoize :flaky
      rescue_from(RuntimeError, :flaky) { :fallback }
    end

    assert_equal :fallback, facade.flaky
    assert_equal :ok, facade.flaky
    assert_equal :ok, facade.flaky
    assert_equal 2, calls
  end

  def test_clear_memos_drops_values_and_returns_self
    calls = 0
    facade = Briefly.define do
      shortcut(:value) { calls += 1 }
      memoize :value
    end

    facade.value

    assert_same facade, facade.briefly.clear_memos!

    facade.value

    assert_equal 2, calls
  end

  def test_reset_bang_is_an_alias_of_clear_memos
    calls = 0
    facade = Briefly.define do
      shortcut(:value) { calls += 1 }
      memoize :value
    end

    facade.value
    facade.briefly.clear_memos!
    facade.value

    assert_equal 2, calls
  end

  def test_unmemoized_shortcuts_are_not_cached
    calls = 0
    facade = Briefly.define { shortcut(:live) { calls += 1 } }

    2.times { facade.live }

    assert_equal 2, calls
  end

  def test_redeclaring_a_shortcut_drops_its_memoization
    calls = 0
    facade = Briefly.define do
      shortcut(:value) { calls += 1 }
      memoize :value
      shortcut(:value) { calls += 1 }
    end

    2.times { facade.value }

    assert_equal 2, calls
  end

  def test_memoize_unknown_shortcut_raises
    assert_raises(Briefly::UnknownShortcutError) { Briefly.define { memoize :nope } }
  end

  def test_memoize_an_argument_taking_shortcut_raises
    error = assert_raises(Briefly::Error) do
      Briefly.define do
        shortcut(:with_args) { |arg| arg }
        memoize :with_args
      end
    end

    assert_match(/cannot memoize with_args/, error.message)
  end

  # `{ |&blk| }` has arity 0, but the memo dispatch never forwards a block, so it must be rejected.
  def test_memoize_a_block_taking_shortcut_raises
    error = assert_raises(Briefly::Error) do
      Briefly.define do
        shortcut(:with_block) { |&blk| blk&.call }
        memoize :with_block
      end
    end

    assert_match(/cannot memoize with_block/, error.message)
  end

  # A memoized shortcut takes no arguments. Passing some must say so, not return the cache.
  def test_a_memoized_shortcut_rejects_arguments
    facade = Briefly.define do
      shortcut(:value, :v) { 1 }
      memoize :value
    end

    assert_equal 0, facade.method(:value).arity
    assert_raises(ArgumentError) { facade.value(:nope) }
    assert_raises(ArgumentError) { facade.v(key: :nope) }
  end

  # The dispatcher raises before any handler is consulted, so this stays a bug, not a fallback.
  def test_an_argument_to_a_memoized_shortcut_is_not_rescued
    facade = Briefly.define do
      shortcut(:value) { 1 }
      memoize :value
      rescue_from(StandardError) { :swallowed }
    end

    assert_raises(ArgumentError) { facade.value(:nope) }
  end

  def test_memoize_rejects_unknown_options
    assert_raises(ArgumentError) do
      Briefly.define do
        shortcut(:value) { 1 }
        memoize :value, pin: true
      end
    end
  end
end
