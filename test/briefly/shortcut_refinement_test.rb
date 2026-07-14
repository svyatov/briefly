# frozen_string_literal: true

require "test_helper"

class ShortcutRefinementTest < BrieflyTest
  def test_refinements_return_the_shortcut_so_they_chain
    sc = after_memoize = after_rescue = nil
    Briefly.define do
      sc = shortcut(:x) { 1 }
      after_memoize = sc.memoize
      after_rescue = sc.rescue_from(StandardError) { :ok }
    end

    assert_same sc, after_memoize
    assert_same sc, after_rescue
  end

  # Covers AE1: a bodiless `shortcut(name)` fetches the shortcut to refine; it never re-declares.
  def test_bodiless_fetch_memoizes_without_redeclaring
    calls = 0
    facade = Briefly.define do
      shortcut(:redis, :r) do
        calls += 1
        :pool
      end
      shortcut(:redis).memoize
    end

    assert_equal :pool, facade.redis
    assert_equal :pool, facade.r
    assert_equal 1, calls, "the alias shares one memo cell and the body ran once"
  end

  # Covers AE2.
  def test_bodiless_fetch_of_an_unknown_shortcut_raises
    assert_raises(Briefly::UnknownShortcutError) { Briefly.define { shortcut(:nope).memoize } }
  end

  # A bodiless call ignores aliases, so passing them means the block was forgotten — raise loudly
  # rather than fetch `:cache` and silently drop `:redis`.
  def test_a_bodiless_call_with_aliases_raises_a_forgotten_block
    error = assert_raises(ArgumentError) do
      Briefly.define do
        shortcut(:cache) { :pool }
        shortcut(:cache, :redis)
      end
    end

    assert_match(/requires a block/, error.message)
  end

  # Covers AE3: the alias resolves to the canonical shortcut.
  def test_bodiless_fetch_resolves_through_an_alias
    calls = 0
    facade = Briefly.define do
      shortcut(:config, :c) { calls += 1 }
      shortcut(:c).memoize
    end

    facade.config
    facade.config

    assert_equal 1, calls
  end

  # Covers AE5: refinements chain in any order to the same configuration — whichever order
  # .memoize and .rescue_from are chained, the handler fires and the later success memoizes.
  def test_refinements_chain_in_either_order
    %i[memoize_first rescue_first].each do |order|
      calls = 0
      facade = Briefly.define do
        sc = shortcut(:x) do
          calls += 1
          raise "boom" if calls == 1

          :ok
        end
        if order == :memoize_first
          sc.memoize.rescue_from(RuntimeError) { :rescued }
        else
          sc.rescue_from(RuntimeError) { :rescued }.memoize
        end
      end

      assert_equal :rescued, facade.x, "#{order}: the handler fires"
      assert_equal :ok, facade.x, "#{order}: the retry runs, the fallback was never memoized"
      assert_equal :ok, facade.x
      assert_equal 2, calls, "#{order}: the success memoized after the rescued first call"
    end
  end

  # Covers R8: a shortcut's own handler is scoped to it and called as a plain, non-facade-bound proc.
  def test_scoped_handler_is_scoped_and_receives_error_and_name
    facade = Briefly.define do
      shortcut(:boom) { raise "kaboom" }.rescue_from(StandardError) { |error, name| [error.message, name] }
      shortcut(:other) { raise "nope" }
    end

    assert_equal ["kaboom", :boom], facade.boom
    assert_raises(RuntimeError) { facade.other }
  end

  def test_scoped_handler_is_not_bound_to_the_facade
    facade = Briefly.define do
      shortcut(:logger) { :facade_logger }
      shortcut(:boom) { raise "kaboom" }.rescue_from(StandardError) { self }
    end

    assert_instance_of Briefly::Builder, facade.boom
  end

  def test_shortcut_rescue_from_requires_a_block
    assert_raises(ArgumentError) do
      Briefly.define { shortcut(:boom) { raise "kaboom" }.rescue_from(StandardError) }
    end
  end
end
