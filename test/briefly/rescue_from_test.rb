# frozen_string_literal: true

require "test_helper"
require "support/variadic_fixture"

class RescueFromTest < BrieflyTest
  class NotStandard < Exception; end # rubocop:disable Lint/InheritException

  # RescueRegistry#add without its mutex. Scale alone does not surface the lost update reliably --
  # 8x500 against the unguarded registry loses nothing in 20 runs -- so the read/write window is held
  # open explicitly. Without this fixture the guard below cannot fail, and pins nothing.
  class UnguardedRegistry < Briefly::RescueRegistry
    def add(klass, handler)
      snapshot = @entries
      Thread.pass
      @entries = [*snapshot, Entry.new(klass, handler)].freeze
      self
    end
  end

  def test_handler_return_value_becomes_the_shortcut_value
    facade = Briefly.define do
      shortcut(:boom) { raise "kaboom" }.rescue_from(StandardError) { "unknown" }
    end

    assert_equal "unknown", facade.boom
  end

  def test_handler_receives_the_error_and_the_shortcut_name
    facade = Briefly.define do
      shortcut(:boom) { raise "kaboom" }.rescue_from(StandardError) { |error, name| [error.message, name] }
    end

    assert_equal ["kaboom", :boom], facade.boom
  end

  def test_handler_may_take_only_the_error
    facade = Briefly.define do
      shortcut(:boom) { raise "kaboom" }.rescue_from(StandardError) { |error| error.message }
    end

    assert_equal "kaboom", facade.boom
  end

  # A handler is `call`ed, not `instance_exec`'d: unlike a shortcut body it is not bound to the
  # facade, so it cannot reach shortcuts by bare name.
  def test_a_handler_is_not_bound_to_the_facade
    facade = Briefly.define do
      shortcut(:logger) { :facade_logger }
      shortcut(:boom) { raise "kaboom" }.rescue_from(StandardError) { self }
    end

    assert_instance_of Briefly::Builder, facade.boom
  end

  def test_a_reraising_handler_propagates
    facade = Briefly.define do
      shortcut(:boom) { raise "kaboom" }.rescue_from(StandardError) { |error| raise error }
    end

    assert_equal "kaboom", assert_raises(RuntimeError) { facade.boom }.message
  end

  # The README's escape hatch for a facade-wide handler: log, then re-raise. A bare `raise` reads
  # `$!`, which stays set only because the handler is called from inside `__call`'s rescue body.
  def test_a_handler_can_bare_raise_to_rethrow_the_original
    raise_line = nil
    facade = Briefly.define do
      raise_line = __LINE__ + 1
      shortcut(:boom) { raise ArgumentError, "kaboom" }
      rescue_from(StandardError) { raise }
    end

    error = assert_raises(ArgumentError) { facade.boom }

    assert_equal "kaboom", error.message
    # The backtrace still points at the body that raised, not at the handler that rethrew.
    assert_match(/rescue_from_test\.rb:#{raise_line}:/, error.backtrace.first)
  end

  def test_an_unhandled_error_propagates_unchanged
    facade = Briefly.define { shortcut(:boom) { raise ArgumentError, "kaboom" } }

    assert_equal "kaboom", assert_raises(ArgumentError) { facade.boom }.message
  end

  def test_errors_outside_standard_error_always_propagate
    facade = Briefly.define do
      shortcut(:boom) { raise NotStandard }.rescue_from(Exception) { :never }
    end

    assert_raises(NotStandard) { facade.boom }
  end

  def test_subclasses_match
    facade = Briefly.define do
      shortcut(:boom) { raise ArgumentError }.rescue_from(StandardError) { :caught }
    end

    assert_equal :caught, facade.boom
  end

  def test_a_narrower_class_does_not_match_a_wider_error
    facade = Briefly.define do
      shortcut(:boom) { raise "kaboom" }.rescue_from(ArgumentError) { :never }
    end

    assert_raises(RuntimeError) { facade.boom }
  end

  def test_scoping_to_other_shortcuts_does_not_apply
    facade = Briefly.define do
      shortcut(:boom) { raise "kaboom" }
      shortcut(:fine) { :fine }.rescue_from(StandardError) { :never }
    end

    assert_raises(RuntimeError) { facade.boom }
  end

  # A bodiless `shortcut(alias)` resolves through the alias to the canonical shortcut.
  def test_a_shortcut_may_be_fetched_through_an_alias
    facade = Briefly.define do
      shortcut(:config, :c) { raise "kaboom" }
      shortcut(:c).rescue_from(StandardError) { :caught }
    end

    assert_equal :caught, facade.config
  end

  def test_last_registered_wins_within_a_level
    facade = Briefly.define do
      shortcut(:boom) { raise "kaboom" }
        .rescue_from(StandardError) { :first }
        .rescue_from(StandardError) { :second }
    end

    assert_equal :second, facade.boom
  end

  # The level above lives on the Shortcut; this one lives in the RescueRegistry. Two facade-wide
  # handlers for one class both land in the same registry, and `handler_for` matches newest-first.
  # Flip `reverse_each` to `each` in rescue_registry.rb and this goes red — the count-only concurrency
  # tests never would.
  def test_last_registered_facade_wide_handler_wins
    facade = Briefly.define do
      shortcut(:boom) { raise "kaboom" }
      rescue_from(StandardError) { :first }
      rescue_from(StandardError) { :second }
    end

    assert_equal :second, facade.boom
  end

  def test_a_shortcuts_own_handler_beats_facade_wide_regardless_of_order
    facade = Briefly.define do
      shortcut(:boom) { raise "kaboom" }.rescue_from(StandardError) { :scoped }
      rescue_from(StandardError) { :wide }
    end

    assert_equal :scoped, facade.boom
  end

  def test_facade_wide_beats_global
    Briefly.rescue_from(StandardError) { :global }
    facade = Briefly.define do
      shortcut(:boom) { raise "kaboom" }
      rescue_from(StandardError) { :wide }
    end

    assert_equal :wide, facade.boom
  end

  def test_global_applies_when_the_facade_has_no_match
    Briefly.rescue_from(StandardError) { :global }
    facade = Briefly.define { shortcut(:boom) { raise "kaboom" } }

    assert_equal :global, facade.boom
  end

  def test_global_handlers_are_shared_by_every_facade
    Briefly.rescue_from(StandardError) { :global }
    one = Briefly.define { shortcut(:boom) { raise "kaboom" } }
    two = Briefly.define { shortcut(:boom) { raise "kaboom" } }

    assert_equal :global, one.boom
    assert_equal :global, two.boom
  end

  # `{}` binds to the nearest token, so `rescue_from StandardError { }` calls a method named
  # `StandardError`. These two forms are the supported ones; both must bind to `rescue_from`.
  def test_do_end_form_binds_the_block
    facade = Briefly.define do
      shortcut(:boom) { raise "kaboom" }
      rescue_from StandardError do |error|
        error.message
      end
    end

    assert_equal "kaboom", facade.boom
  end

  def test_parens_and_braces_form_binds_the_block
    facade = Briefly.define do
      shortcut(:boom) { raise "kaboom" }
      rescue_from(StandardError) { |error| error.message }
    end

    assert_equal "kaboom", facade.boom
  end

  def test_bare_braces_form_does_not_reach_rescue_from
    # eval of a hardcoded literal: the point is to observe how Ruby *parses* this form. Written
    # inline it would be a call to a method named `StandardError`, which this asserts.
    assert_raises(NoMethodError) do
      Briefly.define do
        shortcut(:boom) { raise "kaboom" }
        eval("rescue_from StandardError { |e| e }", binding, __FILE__, __LINE__)
      end
    end
  end

  def test_error_class_must_come_first
    error = assert_raises(ArgumentError) do
      Briefly.define do
        shortcut(:boom) { raise "kaboom" }
        rescue_from(:boom, StandardError) { :never }
      end
    end

    assert_match(/error class first/, error.message)
  end

  def test_requires_a_block
    assert_raises(ArgumentError) do
      Briefly.define do
        shortcut(:boom) { raise "kaboom" }
        rescue_from(StandardError)
      end
    end
  end

  # Covers AE4: any shortcut name on the verb is refused; the message points at the per-shortcut form.
  def test_names_on_the_verb_are_refused
    error = assert_raises(ArgumentError) do
      Briefly.define do
        shortcut(:boom) { raise "kaboom" }
        rescue_from(StandardError, :boom) { :never }
      end
    end

    assert_match(/takes no shortcut names/, error.message)
    assert_match(/shortcut\(name\)\.rescue_from/, error.message)
  end

  def test_several_names_on_the_verb_are_also_refused
    assert_raises(ArgumentError) do
      Briefly.define do
        shortcut(:a) { :a }
        shortcut(:b) { :b }
        rescue_from(StandardError, :a, :b) { :never }
      end
    end
  end

  def test_an_array_of_names_is_also_refused
    assert_raises(ArgumentError) do
      Briefly.define do
        shortcut(:boom) { raise "kaboom" }
        rescue_from(StandardError, [:boom]) { :never }
      end
    end
  end

  def test_global_rescue_from_validates_its_arguments
    assert_raises(ArgumentError) { Briefly.rescue_from(:not_a_class) { :never } }
    assert_raises(ArgumentError) { Briefly.rescue_from(StandardError) }
  end

  def test_global_rescue_from_returns_briefly
    assert_same Briefly, Briefly.rescue_from(StandardError) { :global }
  end

  # Briefly's own dispatch failures must never be laundered into a user's fallback.
  def test_an_internal_lookup_failure_is_not_handled
    facade = Briefly.define do
      shortcut(:ok) { :ok }
      rescue_from(StandardError) { :swallowed }
    end
    defs(facade).delete(:ok)

    assert_raises(KeyError) { facade.ok }
  end

  def test_concurrent_global_registration_loses_no_handlers
    threads = 8.times.map { Thread.new { 500.times { Briefly.rescue_from(StandardError) { :x } } } }
    threads.each(&:join)

    assert_equal 4000, Briefly.rescues.size
  end

  def test_an_unguarded_registry_really_does_lose_concurrent_registrations
    registry = UnguardedRegistry.new
    threads = 4.times.map { Thread.new { 50.times { registry.add(StandardError, proc { :x }) } } }
    threads.each(&:join)

    assert_operator registry.size, :<, 200,
                    "the fixture must lose entries, otherwise the guard above proves nothing"
  end

  # The test above proves a lost update is detectable; it cannot prove #add still guards against one,
  # because the race almost never fires at a scale a suite can afford. Pin the mutex directly: hold it,
  # and #add must block. Delete the synchronize in rescue_registry.rb and this goes red.
  def test_add_holds_the_mutex_while_rebinding_entries
    registry = Briefly::RescueRegistry.new
    mutex = registry.instance_variable_get(:@mutex)
    mutex.lock
    writer = Thread.new { registry.add(StandardError, proc { :x }) }
    Thread.pass until writer.status == "sleep" || !writer.alive?
    blocked = writer.alive?
    mutex.unlock
    writer.join

    assert blocked, "#add must hold @mutex while rebinding @entries"
    assert_equal 1, registry.size
  end

  # A shortcut's public method carries the body's arity, so a bad call raises at the call site, before
  # `__call` and its rescue layer are entered. The distinction a handler can now rely on is *where* the
  # error came from: about the call, or from inside the body.

  def test_a_wrong_arity_call_escapes_a_facade_wide_handler
    facade = swallowing_facade(Briefly::Facade)

    assert_raises(ArgumentError) { facade.env(1) }
    assert_raises(ArgumentError) { facade.greet }
  end

  # Arity is strict at the call site, and a body *is* a call site. The callee raises inside the
  # caller's `__call`, so the caller's handler sees it — the escape above is about the facade's
  # boundary, not about `ArgumentError`.
  def test_a_wrong_arity_call_between_shortcuts_is_seen_by_the_callers_handler
    facade = Briefly.define do
      shortcut(:callee) { |a| a }
      shortcut(:caller_of) { callee(1, 2) }
      rescue_from(StandardError) { :rescued }
    end

    assert_raises(ArgumentError) { facade.callee(1, 2) }
    assert_equal :rescued, facade.caller_of
  end

  def test_a_missing_required_keyword_escapes_a_facade_wide_handler
    facade = swallowing_facade(Briefly::Facade)

    assert_raises(ArgumentError) { facade.fetch }
  end

  def test_an_unknown_keyword_escapes_a_facade_wide_handler
    facade = swallowing_facade(Briefly::Facade)

    assert_raises(ArgumentError) { facade.fetch(key: 1, nope: 2) }
  end

  def test_an_error_raised_inside_a_body_is_still_rescued
    facade = swallowing_facade(Briefly::Facade)

    assert_nil facade.host
  end

  # Without this, the three guards above pin nothing: they would pass against the variadic dispatch too
  # if the handler simply never matched.
  def test_the_variadic_fixture_swallows_the_bad_calls_so_the_guards_bite
    facade = swallowing_facade(VariadicFacade)

    assert_nil facade.env(1)
    assert_nil facade.greet
    assert_nil facade.fetch
    assert_nil facade.fetch(key: 1, nope: 2)
  end

  private

  def swallowing_facade(klass)
    klass.new.briefly.configure do
      shortcut(:env) { "prod" }
      shortcut(:greet) { |name| name }
      shortcut(:fetch) { |key:| key }
      shortcut(:host) { raise "boom" }
      rescue_from(StandardError) { nil }
    end
  end
end
