# frozen_string_literal: true

require "test_helper"
require "support/rails_double"
require "active_support/notifications"
require "ripper"

class RailsPackTest < BrieflyTest
  LIB = File.expand_path("../../lib", __dir__)

  def test_shortcuts_map_to_the_framework
    with_rails do |rails, controller, facade|
      assert_same rails.configuration, facade.config
      assert_same rails.configuration, facade.c
      assert_same rails.configuration.x, facade.config_x
      assert_same rails.configuration.x, facade.x
      assert_same rails.env, facade.env
      assert_same rails.root, facade.root
      assert_same rails.cache, facade.cache
      assert_same rails.logger, facade.logger
      assert_same rails.logger, facade.log
      assert_same rails.application.credentials, facade.credentials
      assert_same rails.application.credentials, facade.cred
      assert_same rails.application.routes.url_helpers, facade.routes
      assert_same rails.application.routes.url_helpers, facade.r
      assert_same controller.helpers, facade.helpers
      assert_same controller.helpers, facade.h
      assert_same controller.renderer, facade.renderer
    end
  end

  # `error` returns the framework's handled-error reporter; `config_for` forwards a per-call YAML read,
  # threading its options (so `config_for(:x, env: "staging")` reaches the framework).
  def test_error_and_config_for_reach_the_framework
    with_rails do |rails, _controller, facade|
      assert_same rails.error, facade.error

      assert_equal({ config_for: :payments }, facade.config_for(:payments))
      facade.config_for(:billing, env: "staging")

      assert_equal [[:payments, {}], [:billing, { env: "staging" }]], rails.application.config_for_calls

      assert facade.briefly.shortcut?(:error)
      assert facade.briefly.shortcut?(:config_for)
      assert_empty memoized_names(facade)
      assert_equal "#{LIB}/briefly/rails/config.rb", facade.method(:config_for).source_location.first
    end
  end

  def test_environment_predicates
    with_rails(env: "production") do |_rails, _controller, facade|
      assert_predicate facade, :production?
      refute_predicate facade, :development?
      refute_predicate facade, :test?
      refute_predicate facade, :local?
    end
  end

  # `dev?`/`prod?` are aliases of the canonical predicates: one shared compiled method, one canonical name.
  def test_dev_and_prod_are_aliases_of_the_canonical_predicates
    with_rails(env: "production") do |_rails, _controller, facade|
      assert_equal facade.method(:development?), facade.method(:dev?)
      assert_equal facade.method(:production?), facade.method(:prod?)

      assert_predicate facade, :prod?
      refute_predicate facade, :dev?
      assert facade.briefly.shortcut?(:prod?)
      assert facade.briefly.shortcut?(:dev?)
    end
  end

  def test_local_predicate_is_true_in_development
    with_rails(env: "development") do |_rails, _controller, facade|
      assert_predicate facade, :local?
    end
  end

  def test_secrets_is_absent_and_credentials_replaces_it
    with_rails do |_rails, _controller, facade|
      refute facade.briefly.shortcut?(:secrets)
      assert facade.briefly.shortcut?(:credentials)
    end
  end

  # Rails already caches helpers/routes/renderer on objects it refreshes on reload.
  def test_the_pack_memoizes_nothing
    with_rails do |_rails, _controller, facade|
      assert_empty memoized_names(facade)
    end
  end

  def test_render_forwards_positional_keyword_and_block_arguments
    with_rails do |_rails, controller, facade|
      assert_equal "rendered", facade.render(:show, layout: false) { :from_block }

      args, kwargs, block_result = controller.renderer.calls.fetch(0)

      assert_equal [:show], args
      assert_equal({ layout: false }, kwargs)
      assert_equal :from_block, block_result
    end
  end

  # Inside `Briefly::Rails`, a bare `Rails` resolves to the pack itself, not the framework. Globbed,
  # not listed: a new pack file must not be able to join the tree without joining this check.
  def test_the_pack_never_references_bare_framework_constants
    files = pack_sources

    assert_operator files.size, :>=, 3, "the glob stopped seeing the pack files"
    files.each do |file|
      assert_empty bare_framework_refs(File.read(file)),
                   "#{file}: bare framework constant; must be `::Rails` / `::ApplicationController`"
    end
  end

  # Without these, the guard above is a silent pass: a regex that only catches dotted calls, whose
  # comment stripping also truncates any line holding a `#` inside a string literal.
  def test_the_discipline_check_catches_what_it_claims_to
    assert_empty bare_framework_refs(%(x = ::Rails.env))
    assert_empty bare_framework_refs(%(module Rails\nend))
    assert_empty bare_framework_refs(%(x = Briefly::Rails.install(y)))
    assert_empty bare_framework_refs(%(# a comment naming Rails.env and ApplicationController.helpers))

    refute_empty bare_framework_refs(%(x = Rails.env)), "bare dotted call"
    refute_empty bare_framework_refs(%(v = Rails::VERSION)), "bare non-dotted reference"
    refute_empty bare_framework_refs(%(use(Rails))), "bare constant as an argument"
    refute_empty bare_framework_refs(%(k = ApplicationController)), "bare constant, no trailing dot"
    refute_empty bare_framework_refs(%(msg = "a # b"; x = Rails.env)), "`#` inside a string literal"
  end

  # A real subscriber captures the event `instrument` fires, and the block's return value survives.
  def test_instrument_fires_a_notification_and_preserves_the_block_result
    events = []
    callback = ->(name, _start, _finish, _id, payload) { events << [name, payload] }

    ActiveSupport::Notifications.subscribed(callback, "evt.name") do
      facade = Briefly.define { use "rails/instrument" }

      assert_equal :body, facade.instrument("evt.name", key: 1) { :body }
    end

    assert_equal [["evt.name", { key: 1 }]], events
  end

  # `payload = {}` is real API: `instrument(name) { }` with no payload must still fire and thread an
  # empty payload. Compiled arity is strict, so dropping the default would break this — but every other
  # test passes a payload, leaving that path unexercised while the 100% coverage gate stays green.
  def test_instrument_defaults_the_payload_when_called_without_one
    seen = []
    callback = ->(_name, _start, _finish, _id, payload) { seen << payload }

    ActiveSupport::Notifications.subscribed(callback, "no.payload") do
      facade = Briefly.define { use "rails/instrument" }

      assert_equal :done, facade.instrument("no.payload") { :done }
    end

    assert_equal [{}], seen
  end

  def test_the_umbrella_exposes_instrument
    with_rails do |_rails, _controller, facade|
      assert facade.briefly.shortcut?(:instrument)

      events = []
      callback = ->(_name, _start, _finish, _id, payload) { events << payload }

      ActiveSupport::Notifications.subscribed(callback, "umbrella.evt") do
        assert_equal :ok, facade.instrument("umbrella.evt", n: 2) { :ok }
      end

      assert_equal [{ n: 2 }], events
    end
  end

  def test_only_install_is_public_on_the_pack
    [Briefly::Rails, Briefly::Rails::Config, Briefly::Rails::Env, Briefly::Rails::View,
     Briefly::Rails::Instrument].each do |pack|
      assert_equal %i[install], pack.singleton_methods(false), pack.name
    end
  end

  def test_the_mini_packs_install_independently
    with_rails do |rails, _controller, _facade|
      assert_equal [:env], Briefly.define { use "rails/env" }.briefly.shortcuts.grep(:env)
      assert_same rails.configuration, Briefly.define { use Briefly::Rails::Config }.config
    end
  end

  def test_an_app_can_override_a_pack_shortcut
    with_rails do |_rails, _controller, facade|
      facade.briefly.configure { shortcut(:config) { "custom" } }

      assert_equal "custom", facade.config
    end
  end

  # The umbrella mounts DB under the `db` namespace and burns no root-level names for it. The pack's
  # own behavior is tested against real Active Record in rails_db_test.
  def test_the_umbrella_mounts_the_db_pack_under_a_namespace
    with_rails do |_rails, _controller, facade|
      assert facade.briefly.shortcut?(:db), "expected a `db` namespace"
      assert facade.db.briefly.shortcut?(:query), "expected DB shortcuts on the child"
      refute facade.briefly.shortcut?(:query), "the umbrella must add no root-level DB names"
      refute facade.briefly.shortcut?(:txn), "the umbrella must add no root-level DB names"
    end
  end

  def test_the_glob_sees_every_pack_file
    assert_includes pack_sources, File.join(LIB, "briefly/rails/db.rb")
    assert_includes pack_sources, File.join(LIB, "briefly/rails/instrument.rb")
    assert_includes pack_sources, File.join(LIB, "briefly/rails/reload.rb")
    assert_includes pack_sources, File.join(LIB, "briefly/rails.rb")
  end

  private

  # Globbed so a pack file added later cannot slip past `bare_framework_refs`.
  def pack_sources = Dir[File.join(LIB, "briefly/rails.rb"), File.join(LIB, "briefly/rails/*.rb")].sort

  # R9: jump-to-definition on a pack's shortcut lands in the pack, not in the initializer that used it.
  def test_a_pack_shortcut_reports_the_packs_own_file
    with_rails do |_rails, _controller, facade|
      assert_equal "#{LIB}/briefly/rails/env.rb", facade.method(:env).source_location.first
      assert_equal "#{LIB}/briefly/rails.rb", facade.method(:db).source_location.first
      assert_equal "#{LIB}/briefly/rails/db.rb", facade.db.method(:query).source_location.first
    end
  end

  def with_rails(root: Dir.pwd, env: "test")
    RailsDouble.with(root: root, env: env) do |rails, controller|
      yield rails, controller, Briefly.define { use Briefly::Rails }
    end
  end

  # Comments cannot affect constant resolution, so drop them via the lexer rather than a regex that
  # would also truncate any line holding a `#` inside a string literal. `module Rails` is the pack's
  # own declaration, not a framework reference.
  def bare_framework_refs(source)
    code = Ripper.lex(source).reject { |(_, type, _)| type == :on_comment }.map { |token| token[2] }.join
    code = code.gsub(/\bmodule\s+Rails\b/, "")
    code.scan(/(?<![:\w])(?:Rails|ApplicationController)\b/)
  end
end
