# frozen_string_literal: true

require "test_helper"
require "support/variadic_fixture"

# The "real methods" thesis, under the reflection APIs a developer reaches for after the first hour.
# Each parity assertion is also pointed at `VariadicFacade`, the dispatch this feature replaced, and
# asserted to fail there.
class ReflectionTest < BrieflyTest
  def test_a_fixed_arity_shortcut_reports_the_bodys_kinds_and_arity
    facade = Briefly.define { shortcut(:add) { |a, b| a + b } }

    assert_equal(%i[req req], facade.method(:add).parameters.map(&:first))
    assert_equal 2, facade.method(:add).arity
  end

  def test_an_optional_shortcut_reports_the_bodys_kinds_and_arity
    facade = Briefly.define { shortcut(:pad) { |s, width = 8| s.ljust(width) } }

    assert_equal(%i[req opt], facade.method(:pad).parameters.map(&:first))
    assert_equal(-2, facade.method(:pad).arity)
    assert_equal "x       ", facade.pad("x")
  end

  def test_a_keyword_shortcut_reports_the_bodys_kinds_and_arity
    facade = Briefly.define { shortcut(:fetch) { |key, ttl: 60| [key, ttl] } }

    assert_equal(%i[req key], facade.method(:fetch).parameters.map(&:first))
    assert_equal(-2, facade.method(:fetch).arity)
    assert_equal [:a, 60], facade.fetch(:a)
    assert_equal [:a, 5], facade.fetch(:a, ttl: 5)
  end

  def test_a_block_taking_shortcut_reports_the_bodys_kinds_and_arity
    facade = Briefly.define { shortcut(:around) { |&blk| blk.call } }

    assert_equal([:block], facade.method(:around).parameters.map(&:first))
    assert_equal 0, facade.method(:around).arity
    assert_equal(:ran, facade.around { :ran })
  end

  def test_a_body_without_a_block_parameter_ignores_a_caller_block
    facade = Briefly.define { shortcut(:env) { "prod" } }

    assert_equal("prod", facade.env { :unused })
  end

  def test_source_location_points_at_the_declaring_block
    line = __LINE__ + 2
    facade = Briefly.define do
      shortcut(:redis) { :pool }
    end

    assert_equal [__FILE__, line], facade.method(:redis).source_location
  end

  def test_no_shortcut_reports_a_location_inside_the_gem
    facade = Briefly.define do
      shortcut(:redis) { :pool }
      namespace(:db) { shortcut(:query) { |sql| sql } }
    end

    locations = [facade.method(:redis), facade.method(:db), facade.db.method(:query)].map do |m|
      m.source_location.first
    end

    assert_equal [__FILE__] * 3, locations
  end

  # A `&:upcase` body is a Proc over a C method, so it carries no `source_location`. The location must
  # still be honest — the declaration site — never a fabricated file. Guards the fallback in `shortcut`.
  def test_a_location_less_proc_body_reports_the_declaration_site
    line = __LINE__ + 2
    facade = Briefly.define do
      shortcut(:up, &:upcase)
    end

    assert_equal [__FILE__, line], facade.method(:up).source_location
    assert_equal "HI", facade.up("hi")
  end

  # A pack is the main way shortcuts are declared, so the location-less fallback must also point at the
  # pack when a pack installs a `&:method` body — the `caller_locations` depth is right from `install` too.
  def test_a_location_less_proc_body_declared_in_a_pack_reports_the_pack
    install_line = __LINE__ + 2
    pack = Class.new do
      def self.install(builder) = builder.shortcut(:up, &:upcase)
    end
    facade = Briefly.define { use pack }

    assert_equal [__FILE__, install_line], facade.method(:up).source_location
    assert_equal "HI", facade.up("hi")
  end

  def test_a_memoized_shortcut_keeps_arity_zero_and_gains_an_honest_location
    line = __LINE__ + 2
    facade = Briefly.define do
      shortcut(:catalog) { :built }
      memoize :catalog
    end

    assert_equal 0, facade.method(:catalog).arity
    assert_equal [__FILE__, line], facade.method(:catalog).source_location
  end

  def test_aliases_report_what_their_canonical_reports
    facade = Briefly.define { shortcut(:configuration, :config, :c) { |scope| scope } }

    canonical = facade.method(:configuration)
    %i[config c].each do |name|
      assert_equal canonical.parameters, facade.method(name).parameters
      assert_equal canonical.arity, facade.method(name).arity
      assert_equal canonical.source_location, facade.method(name).source_location
    end
  end

  def test_a_name_that_is_not_an_identifier_stays_declarable_and_callable
    facade = Briefly.define { shortcut(:"foo bar") { 1 } }

    assert_equal 1, facade.send(:"foo bar")
  end

  # R13: management hides behind a single public accessor, so `RESERVED` takes exactly one name — not
  # five — out of the shortcut namespace. `inspect`/`to_s` are `Object`'s and cost no freedom.
  def test_the_facade_gained_no_public_method
    assert_equal %i[briefly],
                 (Briefly::Facade.instance_methods - Object.instance_methods).sort
  end

  # The other half of R13: `RESERVED` is built from the private helpers too, so one more of those takes
  # one more name out of the shortcut namespace just as surely as a public method would. Compilation
  # therefore lives in `candor`, not here; the four `__`-prefixed management methods are the deliberate,
  # `send`-reached surface behind `briefly`, unreachable as shortcuts because they are prefixed.
  def test_the_facade_gained_no_private_helper
    assert_equal %i[__call __clear_memos! __commit __configure __define __handle __install __memo
                    __prepare __remove_methods __shortcut? __shortcuts],
                 (Briefly::Facade.private_instance_methods(false) - %i[initialize]).sort
  end

  # `Facade::BODY_PREFIX` was removed when fabrication moved to candor (a BREAKING change); compiled
  # bodies now live under `Candor::BODY_PREFIX`. Guard the removal so a refactor can't silently reintroduce it.
  def test_the_facade_no_longer_defines_body_prefix
    refute Briefly::Facade.const_defined?(:BODY_PREFIX), "Facade::BODY_PREFIX should be gone; use Candor::BODY_PREFIX"
  end

  def test_every_reserved_private_name_is_prefixed_and_so_unreachable_as_a_shortcut
    private_names = Briefly::Facade.private_instance_methods(false) - %i[initialize]

    assert_empty(private_names.reject { |name| name.start_with?("__") })
  end

  # The guard above only bites if a bare private name trips it. A fixture that adds one proves the
  # check can fail — without it, the management surface could grow an unprefixed private helper (one
  # more name stolen from the shortcut namespace) and no test would notice.
  def test_the_prefix_guard_bites_an_unprefixed_private_name
    leaky = Class.new(Briefly::Facade) { private def leak = nil }
    private_names = leaky.private_instance_methods(false) - %i[initialize]

    refute_empty(private_names.reject { |name| name.start_with?("__") })
  end

  def test_reconfiguring_emits_no_redefinition_warning
    facade = Briefly.define { shortcut(:env) { "a" } }

    assert_empty(warnings { facade.briefly.configure { shortcut(:env) { "b" } } })
    assert_equal "b", facade.env
  end

  # Guards. Each fails against the fixture carrying the defect it pins.

  def test_the_variadic_fixture_reports_a_lie_so_the_parity_guard_bites
    facade = VariadicFacade.new.briefly.configure { shortcut(:add) { |a, b| a + b } }

    assert_equal(-1, facade.method(:add).arity)
    assert_equal(%i[rest keyrest block], facade.method(:add).parameters.map(&:first))
    assert_equal "variadic_fixture.rb", File.basename(facade.method(:add).source_location.first)
  end

  def test_the_redefining_fixture_warns_so_the_redefinition_guard_bites
    facade = RedefiningFacade.new.briefly.configure { shortcut(:env) { "a" } }

    assert_match(/method redefined/, warnings { facade.briefly.configure { shortcut(:env) { "b" } } }.join)
  end

  # The sentinel marking an unpassed optional must be nameless. `UNSET` is a constant, and
  # `Module#const_get` pierces `private_constant`, so a caller able to name it could pass it and
  # silently take the body's default instead of the argument they wrote.
  def test_the_memo_sentinel_cannot_stand_in_for_an_unpassed_optional
    facade = Briefly.define { shortcut(:pad) { |a, b = :default| [a, b] } }

    assert_equal [1, Briefly::UNSET], facade.pad(1, Briefly::UNSET)
  end

  private

  # Method redefinition is warned by the VM, not by `Kernel#warn`, but both reach `$stderr`.
  def warnings(&)
    verbose = $VERBOSE
    $VERBOSE = true
    _out, err = capture_io(&)
    err.lines.grep(/warning/)
  ensure
    $VERBOSE = verbose
  end
end
