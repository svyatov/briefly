# frozen_string_literal: true

require "test_helper"

# The payoff of hiding management behind one door: the five former lifecycle names are shortcuts again,
# and `App.briefly` exposes the same operations without stealing a name apiece.
class BrieflyAccessorTest < BrieflyTest
  # The five names are free — each defines and dispatches as an ordinary shortcut.

  def test_configure_is_usable_as_a_shortcut
    assert_equal "x", Briefly.define { shortcut(:configure) { "x" } }.configure
  end

  def test_shortcuts_is_usable_as_a_shortcut
    assert_equal "x", Briefly.define { shortcut(:shortcuts) { "x" } }.shortcuts
  end

  def test_clear_memos_bang_is_usable_as_a_shortcut
    assert_equal "x", Briefly.define { shortcut(:clear_memos!) { "x" } }.clear_memos!
  end

  def test_reset_bang_is_usable_as_a_shortcut
    assert_equal "x", Briefly.define { shortcut(:reset!) { "x" } }.reset!
  end

  def test_shortcut_predicate_is_usable_as_a_shortcut
    assert_equal "x", Briefly.define { shortcut(:shortcut?) { "x" } }.shortcut?
  end

  def test_reserved_no_longer_carries_the_freed_names
    %i[shortcuts shortcut? clear_memos! reset! configure].each do |name|
      refute_includes Briefly::Facade::RESERVED, name
    end
    assert_includes Briefly::Facade::RESERVED, :briefly
    assert_includes Briefly::Facade::RESERVED, :raise
  end

  # `App.briefly` exposes each management operation.

  def test_briefly_shortcuts_returns_sorted_canonical_names
    facade = Briefly.define do
      shortcut(:zeta) { 1 }
      shortcut(:alpha, :a) { 2 }
    end

    assert_equal %i[alpha zeta], facade.briefly.shortcuts
  end

  def test_briefly_shortcut_predicate_covers_canonical_alias_and_unknown
    facade = Briefly.define { shortcut(:config, :c) { 1 } }

    assert facade.briefly.shortcut?(:config)
    assert facade.briefly.shortcut?(:c)
    refute facade.briefly.shortcut?(:nope)
  end

  def test_briefly_clear_memos_returns_the_facade_and_recomputes
    calls = 0
    facade = Briefly.define do
      shortcut(:n) { calls += 1 }
      memoize :n
    end
    facade.n
    facade.n

    assert_equal 1, calls
    assert_same facade, facade.briefly.clear_memos!

    facade.n

    assert_equal 2, calls
  end

  def test_briefly_configure_returns_the_facade_and_installs
    facade = Briefly.define { shortcut(:kept) { :kept } }
    result = facade.briefly.configure { shortcut(:added) { :added } }

    assert_same facade, result
    assert_equal :added, facade.added
  end

  def test_briefly_configure_that_raises_leaves_the_facade_untouched
    facade = Briefly.define { shortcut(:kept) { :kept } }

    assert_raises(Briefly::ReservedNameError) do
      facade.briefly.configure do
        shortcut(:ok) { 1 }
        shortcut(:class) { 2 } # reserved — the whole pass must roll back
      end
    end

    refute facade.briefly.shortcut?(:ok)
    assert_equal %i[kept], facade.briefly.shortcuts
  end

  def test_briefly_clear_memos_on_a_namespace_scopes_to_the_child
    root_calls = 0
    child_calls = 0
    facade = Briefly.define do
      shortcut(:val) { root_calls += 1 }
      memoize :val
      namespace(:db) do
        shortcut(:val) { child_calls += 1 }
        memoize :val
      end
    end
    facade.val
    facade.db.val

    facade.db.briefly.clear_memos!
    facade.val     # root memo survives
    facade.db.val  # child memo was cleared, recomputes

    assert_equal 1, root_calls
    assert_equal 2, child_calls
  end

  def test_reset_is_absent_from_the_facade_unless_defined_as_a_shortcut
    refute_respond_to Briefly.define, :reset!
    assert_respond_to Briefly.define { shortcut(:reset!) { 1 } }, :reset!
  end

  def test_briefly_control_inspect_names_its_management_operations
    inspected = Briefly.define.briefly.inspect

    assert_match(/Briefly::Facade::Control/, inspected)
    %w[shortcuts shortcut? clear_memos! configure].each { |op| assert_includes inspected, op }
  end

  # The cascade reaches each child's private `__clear_memos!` via `send`, so a child that reclaims
  # `clear_memos!` as a shortcut cannot hijack the tree-wide clear — the freed name and the internal
  # clear coexist. This is what the `&:clear_memos!` -> `send(:__clear_memos!)` change protects.
  def test_clear_memos_cascade_ignores_a_same_named_child_shortcut
    child_calls = 0
    facade = Briefly.define do
      namespace(:db) do
        shortcut(:val) { child_calls += 1 }
        memoize :val
        shortcut(:clear_memos!) { :the_shortcut }
      end
    end
    facade.db.val

    facade.briefly.clear_memos!
    facade.db.val

    assert_equal 2, child_calls
    assert_equal :the_shortcut, facade.db.clear_memos!
  end

  # Control identity is deliberately not asserted: `briefly` returns a fresh `Control` each call
  # (KTD3), so two calls need not be `equal?`. Tests must not pin identity on it.
end
