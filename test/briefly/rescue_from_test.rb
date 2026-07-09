# frozen_string_literal: true

require "test_helper"

class RescueFromTest < BrieflyTest
  class NotStandard < Exception; end # rubocop:disable Lint/InheritException

  # ErrorRegistry#add without its mutex. Scale alone does not surface the lost update reliably --
  # 8x500 against the unguarded registry loses nothing in 20 runs -- so the read/write window is held
  # open explicitly. Without this fixture the guard below cannot fail, and pins nothing.
  class UnguardedRegistry < Briefly::ErrorRegistry
    def add(klass, names, handler)
      snapshot = @entries
      Thread.pass
      @entries = [*snapshot, Entry.new(klass, names&.freeze, handler)].freeze
      self
    end
  end

  def test_handler_return_value_becomes_the_shortcut_value
    facade = Briefly.new do
      shortcut(:boom) { raise "kaboom" }
      rescue_from(StandardError, :boom) { "unknown" }
    end

    assert_equal "unknown", facade.boom
  end

  def test_handler_receives_the_error_and_the_shortcut_name
    facade = Briefly.new do
      shortcut(:boom) { raise "kaboom" }
      rescue_from(StandardError, :boom) { |error, name| [error.message, name] }
    end

    assert_equal ["kaboom", :boom], facade.boom
  end

  def test_handler_may_take_only_the_error
    facade = Briefly.new do
      shortcut(:boom) { raise "kaboom" }
      rescue_from(StandardError, :boom) { |error| error.message }
    end

    assert_equal "kaboom", facade.boom
  end

  # A handler is `call`ed, not `instance_exec`'d: unlike a shortcut body it is not bound to the
  # facade, so it cannot reach shortcuts by bare name.
  def test_a_handler_is_not_bound_to_the_facade
    facade = Briefly.new do
      shortcut(:logger) { :facade_logger }
      shortcut(:boom) { raise "kaboom" }
      rescue_from(StandardError, :boom) { self }
    end

    assert_instance_of Briefly::Builder, facade.boom
  end

  def test_a_reraising_handler_propagates
    facade = Briefly.new do
      shortcut(:boom) { raise "kaboom" }
      rescue_from(StandardError, :boom) { |error| raise error }
    end

    assert_equal "kaboom", assert_raises(RuntimeError) { facade.boom }.message
  end

  # The README's escape hatch for a facade-wide handler: log, then re-raise. A bare `raise` reads
  # `$!`, which stays set only because the handler is called from inside `__call`'s rescue body.
  def test_a_handler_can_bare_raise_to_rethrow_the_original
    raise_line = nil
    facade = Briefly.new do
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
    facade = Briefly.new { shortcut(:boom) { raise ArgumentError, "kaboom" } }

    assert_equal "kaboom", assert_raises(ArgumentError) { facade.boom }.message
  end

  def test_errors_outside_standard_error_always_propagate
    facade = Briefly.new do
      shortcut(:boom) { raise NotStandard }
      rescue_from(Exception, :boom) { :never }
    end

    assert_raises(NotStandard) { facade.boom }
  end

  def test_subclasses_match
    facade = Briefly.new do
      shortcut(:boom) { raise ArgumentError }
      rescue_from(StandardError, :boom) { :caught }
    end

    assert_equal :caught, facade.boom
  end

  def test_a_narrower_class_does_not_match_a_wider_error
    facade = Briefly.new do
      shortcut(:boom) { raise "kaboom" }
      rescue_from(ArgumentError, :boom) { :never }
    end

    assert_raises(RuntimeError) { facade.boom }
  end

  def test_scoping_to_other_shortcuts_does_not_apply
    facade = Briefly.new do
      shortcut(:boom) { raise "kaboom" }
      shortcut(:fine) { :fine }
      rescue_from(StandardError, :fine) { :never }
    end

    assert_raises(RuntimeError) { facade.boom }
  end

  def test_names_may_be_given_as_an_array
    facade = Briefly.new do
      shortcut(:a) { raise "a" }
      shortcut(:b) { raise "b" }
      rescue_from(StandardError, %i[a b]) { |error| error.message }
    end

    assert_equal "a", facade.a
    assert_equal "b", facade.b
  end

  def test_names_may_be_aliases
    facade = Briefly.new do
      shortcut(:config, :c) { raise "kaboom" }
      rescue_from(StandardError, :c) { :caught }
    end

    assert_equal :caught, facade.config
  end

  def test_last_registered_wins_within_a_level
    facade = Briefly.new do
      shortcut(:boom) { raise "kaboom" }
      rescue_from(StandardError, :boom) { :first }
      rescue_from(StandardError, :boom) { :second }
    end

    assert_equal :second, facade.boom
  end

  def test_facade_scoped_beats_facade_wide_regardless_of_order
    facade = Briefly.new do
      shortcut(:boom) { raise "kaboom" }
      rescue_from(StandardError, :boom) { :scoped }
      rescue_from(StandardError) { :wide }
    end

    assert_equal :scoped, facade.boom
  end

  def test_facade_wide_beats_global
    Briefly.rescue_from(StandardError) { :global }
    facade = Briefly.new do
      shortcut(:boom) { raise "kaboom" }
      rescue_from(StandardError) { :wide }
    end

    assert_equal :wide, facade.boom
  end

  def test_global_applies_when_the_facade_has_no_match
    Briefly.rescue_from(StandardError) { :global }
    facade = Briefly.new { shortcut(:boom) { raise "kaboom" } }

    assert_equal :global, facade.boom
  end

  def test_global_handlers_are_shared_by_every_facade
    Briefly.rescue_from(StandardError) { :global }
    one = Briefly.new { shortcut(:boom) { raise "kaboom" } }
    two = Briefly.new { shortcut(:boom) { raise "kaboom" } }

    assert_equal :global, one.boom
    assert_equal :global, two.boom
  end

  # `{}` binds to the nearest token, so `rescue_from StandardError { }` calls a method named
  # `StandardError`. These two forms are the supported ones; both must bind to `rescue_from`.
  def test_do_end_form_binds_the_block
    facade = Briefly.new do
      shortcut(:boom) { raise "kaboom" }
      rescue_from StandardError, :boom do |error|
        error.message
      end
    end

    assert_equal "kaboom", facade.boom
  end

  def test_parens_and_braces_form_binds_the_block
    facade = Briefly.new do
      shortcut(:boom) { raise "kaboom" }
      rescue_from(StandardError, :boom) { |error| error.message }
    end

    assert_equal "kaboom", facade.boom
  end

  def test_bare_braces_form_does_not_reach_rescue_from
    # eval of a hardcoded literal: the point is to observe how Ruby *parses* this form. Written
    # inline it would be a call to a method named `StandardError`, which this asserts.
    assert_raises(NoMethodError) do
      Briefly.new do
        shortcut(:boom) { raise "kaboom" }
        eval("rescue_from StandardError { |e| e }", binding, __FILE__, __LINE__)
      end
    end
  end

  def test_error_class_must_come_first
    error = assert_raises(ArgumentError) do
      Briefly.new do
        shortcut(:boom) { raise "kaboom" }
        rescue_from(:boom, StandardError) { :never }
      end
    end

    assert_match(/error class first/, error.message)
  end

  def test_requires_a_block
    assert_raises(ArgumentError) do
      Briefly.new do
        shortcut(:boom) { raise "kaboom" }
        rescue_from(StandardError, :boom)
      end
    end
  end

  def test_unknown_shortcut_name_raises
    assert_raises(Briefly::UnknownShortcutError) { Briefly.new { rescue_from(StandardError, :nope) { :never } } }
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
    facade = Briefly.new do
      shortcut(:ok) { :ok }
      rescue_from(StandardError) { :swallowed }
    end
    defs(facade).delete(:ok)

    assert_raises(KeyError) { facade.ok }
  end

  def test_concurrent_global_registration_loses_no_handlers
    threads = 8.times.map { Thread.new { 500.times { Briefly.rescue_from(StandardError) { :x } } } }
    threads.each(&:join)

    assert_equal 4000, Briefly.errors.wide.size
  end

  def test_an_unguarded_registry_really_does_lose_concurrent_registrations
    registry = UnguardedRegistry.new
    threads = 4.times.map { Thread.new { 50.times { registry.add(StandardError, nil, proc { :x }) } } }
    threads.each(&:join)

    assert_operator registry.wide.size, :<, 200,
                    "the fixture must lose entries, otherwise the guard above proves nothing"
  end

  # The test above proves a lost update is detectable; it cannot prove #add still guards against one,
  # because the race almost never fires at a scale a suite can afford. Pin the mutex directly: hold it,
  # and #add must block. Delete the synchronize in error_registry.rb and this goes red.
  def test_add_holds_the_mutex_while_rebinding_entries
    registry = Briefly::ErrorRegistry.new
    mutex = registry.instance_variable_get(:@mutex)
    mutex.lock
    writer = Thread.new { registry.add(StandardError, nil, proc { :x }) }
    Thread.pass until writer.status == "sleep" || !writer.alive?
    blocked = writer.alive?
    mutex.unlock
    writer.join

    assert blocked, "#add must hold @mutex while rebinding @entries"
    assert_equal 1, registry.wide.size
  end
end
