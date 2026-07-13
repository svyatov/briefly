# frozen_string_literal: true

require "test_helper"

class ShortcutTest < BrieflyTest
  def test_defines_real_methods_for_canonical_and_aliases
    facade = Briefly.define { shortcut(:config, :c, :cfg) { :value } }

    assert_respond_to facade, :config
    assert_respond_to facade, :c
    assert_includes facade.methods, :cfg
    assert_equal :value, facade.config
    assert_equal :value, facade.c
    assert_equal :value, facade.cfg
  end

  def test_body_is_bound_to_the_facade_so_it_can_call_other_shortcuts
    facade = Briefly.define do
      shortcut(:base) { 21 }
      shortcut(:doubled) { base * 2 }
    end

    assert_equal 42, facade.doubled
  end

  def test_forwards_positional_arguments
    facade = Briefly.define { shortcut(:echo) { |*args| args } }

    assert_equal [1, 2], facade.echo(1, 2)
  end

  def test_forwards_keyword_arguments
    facade = Briefly.define { shortcut(:echo) { |**kwargs| kwargs } }

    assert_equal({ a: 1 }, facade.echo(a: 1))
  end

  # Regression: an `instance_exec`-based dispatch spends the block slot on the body itself and
  # silently hands the shortcut a nil block, which quietly breaks the Rails pack's `render`.
  def test_forwards_the_callers_block
    facade = Briefly.define { shortcut(:with_block) { |*args, &blk| [args, blk&.call] } }

    assert_equal [[1], :yielded], facade.with_block(1) { :yielded }
  end

  def test_allows_predicate_and_bang_names
    facade = Briefly.define do
      shortcut(:ready?) { true }
      shortcut(:go!) { :went }
    end

    assert_predicate facade, :ready?
    assert_equal :went, facade.go!
  end

  def test_body_arity_is_strict
    facade = Briefly.define { shortcut(:none) { :ok } }

    assert_raises(ArgumentError) { facade.none(1) }
  end

  def test_redefinition_wins
    facade = Briefly.define do
      shortcut(:x) { :first }
      shortcut(:x) { :second }
    end

    assert_equal :second, facade.x
  end

  def test_redefinition_drops_stale_aliases
    facade = Briefly.define { shortcut(:config, :c) { :first } }
    facade.briefly.configure { shortcut(:config) { :second } }

    refute facade.briefly.shortcut?(:c)
    refute_respond_to facade, :c
    assert_equal :second, facade.config
  end

  def test_promoting_an_alias_to_canonical_leaves_the_original
    facade = Briefly.define do
      shortcut(:a, :b) { :from_a }
      shortcut(:b) { :from_b }
    end

    assert_equal %i[a b], facade.briefly.shortcuts
    assert_equal :from_a, facade.a
    assert_equal :from_b, facade.b
  end

  def test_aliasing_over_an_existing_canonical_replaces_it
    facade = Briefly.define do
      shortcut(:a) { :from_a }
      shortcut(:b, :a) { :from_b }
    end

    assert_equal %i[b], facade.briefly.shortcuts
    assert_equal :from_b, facade.a
  end

  def test_reserved_canonical_name_raises
    error = assert_raises(Briefly::ReservedNameError) { Briefly.define { shortcut(:class) { 1 } } }

    assert_match(/class is reserved/, error.message)
  end

  def test_reserved_alias_raises
    assert_raises(Briefly::ReservedNameError) { Briefly.define { shortcut(:fine, :send) { 1 } } }
  end

  # The facade's public surface is now `inspect`, `to_s`, and the `briefly` accessor — those three stay
  # reserved. The five former lifecycle names moved behind `briefly` and are free again (see
  # `briefly_accessor_test.rb`).
  def test_reserved_public_surface_names_raise
    %i[inspect to_s briefly].each do |name|
      assert_raises(Briefly::ReservedNameError) { Briefly.define { shortcut(name) { 1 } } }
    end
  end

  # `Facade#__handle` re-raises unhandled errors. A shortcut named `raise` would shadow Kernel#raise
  # on the facade and recurse until SystemStackError, so the name is reserved.
  def test_raise_is_reserved
    assert_raises(Briefly::ReservedNameError) { Briefly.define { shortcut(:raise) { :nope } } }
  end

  def test_an_unhandled_error_still_propagates_when_a_shortcut_shadows_kernel_privates
    facade = Briefly.define do
      shortcut(:format) { :not_kernel_format }
      shortcut(:boom) { Integer("nope") }
    end

    assert_raises(ArgumentError) { facade.boom }
  end

  # Compiled bodies live in candor's `__candor_body_*` namespace; a shortcut there would overwrite one.
  # Briefly refuses it in `validate_name!`, as the name is declared — candor's own refusal comes too late.
  def test_the_compiled_body_namespace_is_reserved
    hijack = Candor.body_name(:foo)
    error = assert_raises(Briefly::ReservedNameError) do
      Briefly.define do
        shortcut(:foo) { :real }
        shortcut(hijack) { :hijacked }
      end
    end

    assert_match(/compiled shortcut bodies/, error.message)
  end

  def test_dsl_verbs_are_not_reserved_because_the_dsl_lives_on_the_builder
    facade = Briefly.define do
      shortcut(:use) { :use }
      shortcut(:memoize) { :memoize }
    end

    assert_equal :use, facade.use
    assert_equal :memoize, facade.memoize
  end

  def test_shortcut_requires_a_block
    assert_raises(ArgumentError) { Briefly.define { shortcut(:x) } }
  end

  def test_shortcut_names_must_be_symbols
    assert_raises(ArgumentError) { Briefly.define { shortcut("x") { 1 } } }
  end

  def test_shortcut_returns_the_canonical_name
    name = nil
    Briefly.define { name = shortcut(:x, :y) { 1 } }

    assert_equal :x, name
  end
end
