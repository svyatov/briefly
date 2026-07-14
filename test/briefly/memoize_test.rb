# frozen_string_literal: true

require "test_helper"

class MemoizeTest < BrieflyTest
  def test_body_runs_once
    calls = 0
    facade = Briefly.define { shortcut(:value) { calls += 1 }.memoize }

    3.times { facade.value }

    assert_equal 1, calls
  end

  def test_memoizes_nil
    calls = 0
    facade = Briefly.define do
      shortcut(:nothing) do
        calls += 1
        nil
      end.memoize
    end

    assert_nil facade.nothing
    assert_nil facade.nothing
    assert_equal 1, calls
  end

  def test_memoizes_false
    facade = Briefly.define { shortcut(:no) { false }.memoize }

    refute facade.no
    refute facade.no
  end

  def test_aliases_share_one_memo_cell
    calls = 0
    facade = Briefly.define { shortcut(:value, :v) { calls += 1 }.memoize }

    facade.value
    facade.v

    assert_equal 1, calls
  end

  def test_memoize_accepts_an_alias
    calls = 0
    facade = Briefly.define do
      shortcut(:value, :v) { calls += 1 }
      shortcut(:v).memoize
    end

    facade.value
    facade.value

    assert_equal 1, calls
  end

  def test_memoize_returns_the_shortcut
    declared = returned = nil
    Briefly.define do
      declared = shortcut(:value, :v) { 1 }
      returned = declared.memoize
    end

    assert_same declared, returned
  end

  # A transient failure must be retried on the next access, never pinned.
  def test_a_rescued_fallback_is_not_memoized
    calls = 0
    facade = Briefly.define do
      flaky = shortcut(:flaky) do
        calls += 1
        raise "transient" if calls == 1

        :ok
      end
      flaky.memoize.rescue_from(RuntimeError) { :fallback }
    end

    assert_equal :fallback, facade.flaky
    assert_equal :ok, facade.flaky
    assert_equal :ok, facade.flaky
    assert_equal 2, calls
  end

  def test_clear_memos_drops_values_and_returns_self
    calls = 0
    facade = Briefly.define { shortcut(:value) { calls += 1 }.memoize }

    facade.value

    assert_same facade, facade.briefly.clear_memos!

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
      shortcut(:value) { calls += 1 }.memoize
      shortcut(:value) { calls += 1 }
    end

    2.times { facade.value }

    assert_equal 2, calls
  end

  # The top-level `memoize` verb is gone; the shortcut's `#memoize` is the only way to memoize.
  def test_the_top_level_memoize_verb_is_removed
    assert_raises(NoMethodError) { Briefly.define { memoize :nope } }
  end

  def test_memoize_unknown_shortcut_raises
    assert_raises(Briefly::UnknownShortcutError) { Briefly.define { shortcut(:nope).memoize } }
  end

  def test_memoize_an_argument_taking_shortcut_raises
    error = assert_raises(Briefly::Error) do
      Briefly.define { shortcut(:with_args) { |arg| arg }.memoize }
    end

    assert_match(/cannot memoize with_args/, error.message)
  end

  # `{ |&blk| }` has arity 0, but the memo dispatch never forwards a block, so it must be rejected.
  def test_memoize_a_block_taking_shortcut_raises
    error = assert_raises(Briefly::Error) do
      Briefly.define { shortcut(:with_block) { |&blk| blk&.call }.memoize }
    end

    assert_match(/cannot memoize with_block/, error.message)
  end

  # A memoized shortcut takes no arguments. Passing some must say so, not return the cache.
  def test_a_memoized_shortcut_rejects_arguments
    facade = Briefly.define { shortcut(:value, :v) { 1 }.memoize }

    assert_equal 0, facade.method(:value).arity
    assert_raises(ArgumentError) { facade.value(:nope) }
    assert_raises(ArgumentError) { facade.v(key: :nope) }
  end

  # The dispatcher raises before any handler is consulted, so this stays a bug, not a fallback.
  def test_an_argument_to_a_memoized_shortcut_is_not_rescued
    facade = Briefly.define do
      shortcut(:value) { 1 }.memoize
      rescue_from(StandardError) { :swallowed }
    end

    assert_raises(ArgumentError) { facade.value(:nope) }
  end
end
