# frozen_string_literal: true

require "test_helper"

class NamespaceTest < BrieflyTest
  module DbPack
    module_function

    def install(builder)
      builder.shortcut(:query) { |sql| "ran #{sql}" }
      builder
    end
  end

  def test_a_namespace_answers_to_its_name_with_a_child_facade
    facade = Briefly.define { namespace(:db) { shortcut(:query) { :queried } } }

    assert_kind_of Briefly::Facade, facade.db
    assert_equal :queried, facade.db.query
  end

  def test_the_namespace_is_a_shortcut_like_any_other
    facade = Briefly.define { namespace(:db) { shortcut(:query) { :queried } } }

    assert facade.shortcut?(:db)
    assert_equal [:db], facade.shortcuts
    assert_equal [:query], facade.db.shortcuts
    refute facade.shortcut?(:query)
  end

  def test_the_same_child_comes_back_on_every_call
    facade = Briefly.define { namespace(:db) { shortcut(:query) { :queried } } }

    assert_same facade.db, facade.db
  end

  # `define_method` compiles the body, so its zero-parameter arity is enforced.
  def test_a_namespace_takes_no_arguments
    facade = Briefly.define { namespace(:db) { shortcut(:query) { :queried } } }

    assert_raises(ArgumentError) { facade.db(1) }
  end

  def test_a_namespace_takes_a_pack
    facade = Briefly.define { namespace(:db) { use DbPack } }

    assert_equal "ran select 1", facade.db.query("select 1")
  end

  def test_namespaces_nest
    facade = Briefly.define { namespace(:a) { namespace(:b) { shortcut(:c) { :deep } } } }

    assert_equal :deep, facade.a.b.c
  end

  def test_a_child_body_reaches_a_sibling_shortcut_by_bare_name
    facade = Briefly.define do
      namespace(:db) do
        shortcut(:prefix) { "db:" }
        shortcut(:query) { |sql| "#{prefix}#{sql}" }
      end
    end

    assert_equal "db:select 1", facade.db.query("select 1")
  end

  def test_clear_memos_cascades_into_namespaces
    calls = 0
    facade = Briefly.define do
      namespace(:db) do
        shortcut(:pool) { calls += 1 }
        memoize(:pool)
      end
    end

    facade.db.pool
    facade.db.pool

    assert_equal 1, calls

    facade.clear_memos!
    facade.db.pool

    assert_equal 2, calls
  end

  def test_reconfiguring_a_namespace_keeps_the_child_and_its_memos
    calls = 0
    facade = Briefly.define do
      namespace(:db) do
        shortcut(:pool) { calls += 1 }
        memoize(:pool)
      end
    end
    child = facade.db
    facade.db.pool

    facade.configure { namespace(:db) { shortcut(:extra) { :extra } } }

    assert_same child, facade.db
    assert_equal :extra, facade.db.extra

    facade.db.pool

    assert_equal 1, calls
  end

  # How an app extends a namespace a pack already declared, without losing the pack's shortcuts.
  def test_a_second_namespace_call_in_the_same_pass_extends_the_child
    facade = Briefly.define do
      namespace(:db) { use DbPack }
      namespace(:db) { shortcut(:health) { :ok } }
    end

    assert_equal %i[health query], facade.db.shortcuts
    assert_equal "ran select 1", facade.db.query("select 1")
    assert_equal :ok, facade.db.health
  end

  def test_a_namespace_needs_a_block
    assert_raises(ArgumentError) { Briefly.define { namespace(:db) } }
  end

  def test_a_namespace_may_not_shadow_a_facade_method
    assert_raises(Briefly::ReservedNameError) { Briefly.define { namespace(:inspect) { nil } } }
  end

  def test_a_shortcut_overrides_a_namespace_of_the_same_name
    facade = Briefly.define do
      namespace(:db) { shortcut(:query) { :queried } }
      shortcut(:db) { :plain }
    end

    assert_equal :plain, facade.db
  end

  # The overridden child is unreachable, so holding it would only keep `clear_memos!` walking a facade
  # nothing can call — and, if a pack wired `Reload` inside it, keep it alive across every reload.
  def test_a_shortcut_overriding_a_namespace_drops_the_orphaned_child
    facade = Briefly.define do
      namespace(:db) { shortcut(:query) { :queried } }
      shortcut(:db) { :plain }
    end

    assert_empty children(facade)
  end

  # A raising child pass aborts the parent's pass, so neither facade is left half-configured.
  def test_a_raising_namespace_block_leaves_both_facades_untouched
    facade = Briefly.define { shortcut(:kept) { :kept } }

    assert_raises(Briefly::ReservedNameError) do
      facade.configure { namespace(:db) { shortcut(:inspect) { nil } } }
    end

    assert_equal [:kept], facade.shortcuts
    refute facade.shortcut?(:db)
  end

  # The child is created in a copy of `@__children`; only a pass that reaches the end commits it.
  def test_a_pass_that_raises_after_a_namespace_leaves_the_child_unreachable
    facade = Briefly.define { shortcut(:kept) { :kept } }

    assert_raises(Briefly::ReservedNameError) do
      facade.configure do
        namespace(:db) { shortcut(:query) { :queried } }
        shortcut(:inspect) { nil }
      end
    end

    refute facade.shortcut?(:db)
    refute_respond_to facade, :db
  end

  # The child of an *existing* namespace is already reachable, so it is the one thing a half-applied
  # pass could leave mutated. Nothing installs until the whole tree has validated.
  def test_a_pass_that_raises_after_reconfiguring_an_existing_namespace_leaves_the_child_untouched
    facade = Briefly.define { namespace(:db) { shortcut(:query) { :queried } } }

    assert_raises(Briefly::ReservedNameError) do
      facade.configure do
        namespace(:db) { shortcut(:added) { :added } }
        shortcut(:inspect) { nil }
      end
    end

    assert_equal [:query], facade.db.shortcuts
  end

  # Sibling namespaces commit together: a later one's failure cannot leave an earlier one mutated.
  def test_a_raising_namespace_leaves_an_earlier_namespace_in_the_same_pass_untouched
    facade = Briefly.define do
      namespace(:a) { shortcut(:kept) { :kept } }
      namespace(:b) { shortcut(:kept) { :kept } }
    end

    assert_raises(Briefly::ReservedNameError) do
      facade.configure do
        namespace(:a) { shortcut(:added) { :added } }
        namespace(:b) { shortcut(:inspect) { nil } }
      end
    end

    assert_equal [:kept], facade.a.shortcuts
    assert_equal [:kept], facade.b.shortcuts
  end

  # A namespace owns its error registry. The global one is still consulted, via the child's own handler.
  def test_a_global_rescue_from_reaches_into_a_namespace
    Briefly.rescue_from(ArgumentError) { :recovered }
    facade = Briefly.define { namespace(:db) { shortcut(:query) { raise ArgumentError } } }

    assert_equal :recovered, facade.db.query
  end
end
