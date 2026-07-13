# frozen_string_literal: true

require "test_helper"
require "support/rails_double"
require "erb"
require "ripper"

# The install generator is thin Rails-API glue (one `template` call). Running it live would pull in
# railties, which this project deliberately avoids (see the Gemfile), so `lib/generators` is filtered
# out of coverage on purpose (test_helper's SimpleCov block) and pinned two cheaper ways instead:
# structural asserts on the generator's own literals, and — the part that actually rots — a drift guard
# holding the template's self-documenting card to the real umbrella facade.
class InstallGeneratorTest < BrieflyTest
  GENERATOR = File.expand_path("../../lib/generators/briefly/install/install_generator.rb", __dir__)
  TEMPLATE  = File.expand_path("../../lib/generators/briefly/install/templates/briefly.rb.tt", __dir__)

  def test_the_template_renders_to_valid_ruby_under_the_chosen_constant
    rendered = render

    refute_nil Ripper.sexp(rendered), "the generated initializer is not valid Ruby"
    assert_includes rendered, "App = Briefly.define do"
    assert_includes render(name: "Facade"), "Facade = Briefly.define do"

    # Every reference must be interpolated, never a literal `App.` — a hardcoded one would render
    # unchanged under the default name and so slip past the drift guard, which renders as `App`.
    refute_includes render(name: "Facade"), "App.", "template hardcodes `App.` instead of the chosen name"
  end

  # Nothing runs the generator (no railties), so pin the literals a typo would silently break: the
  # template it renders, the destination it writes, and its base class (the `::Rails` discipline).
  def test_the_generator_wires_its_template_and_destination
    source = File.read(GENERATOR)

    assert_includes source, %(template "briefly.rb.tt", "config/initializers/briefly.rb")
    assert_includes source, "class InstallGenerator < ::Rails::Generators::Base"
    assert_path_exists File.expand_path("templates/briefly.rb.tt", File.dirname(GENERATOR))
  end

  # The card must name exactly the shortcuts `use "rails"` installs — no stale name, no omission — so a
  # pack that gains, drops or renames a shortcut can't leave the card's names out of sync. It pins the
  # name+alias set only: the concern grouping and the right-hand descriptions are hand-written prose and
  # are not verified here.
  def test_the_card_lists_exactly_the_shortcuts_the_rails_pack_installs
    with_umbrella do |facade|
      rendered = render

      assert_equal real_names(facade), card_names(rendered), "the root shortcut card drifted from the pack"
      assert_equal real_names(facade.db), card_db_names(rendered), "the db shortcut card drifted from the pack"
    end
  end

  # Guards the guard: a card that omits a real shortcut, or names one that does not exist, must fail the
  # comparison above — proven at both ends for the root card and the db card, since each is a separate
  # assertion that could rot independently.
  def test_the_drift_guard_catches_a_missing_or_stale_entry_at_root_and_in_db
    with_umbrella do |facade|
      refute_equal real_names(facade), card_names("App.config App.c App.root"),
                   "a root card omitting most shortcuts must not pass"
      refute_equal real_names(facade), card_names("#{render}\n#   App.nonexistent"),
                   "a root card naming a nonexistent shortcut must not pass"

      refute_equal real_names(facade.db), card_db_names("App.db.connection App.db.conn"),
                   "a db card omitting most shortcuts must not pass"
      refute_equal real_names(facade.db), card_db_names("#{render}\n#   App.db.nonexistent"),
                   "a db card naming a nonexistent shortcut must not pass"

      # Even a single dropped alias (built from the real set so this can't couple to card formatting)
      # must fail — set equality catches it exactly as it catches a wholesale omission.
      one_alias_short = (real_names(facade) - [:c]).map { |name| "App.#{name}" }.join(" ")

      refute_equal real_names(facade), card_names(one_alias_short), "dropping one alias must not pass"
    end
  end

  private

  # `trim_mode: "-"` mirrors Thor's own `template` render, so a future `<%- -%>` tag can't let this
  # test pass green while the real generator emits something different.
  def render(name: "App") = ERB.new(File.read(TEMPLATE), trim_mode: "-").result_with_hash(name: name)

  def with_umbrella(&) = RailsDouble.with(root: Dir.pwd) { yield Briefly.define { use Briefly::Rails } }

  # Every name a facade answers to: canonical shortcuts plus their aliases, sorted.
  def real_names(facade) = defs(facade).each_value.flat_map(&:names).sort

  # Only the reference card below the divider is pinned; the editable definition above it — where a user
  # grows their own shortcuts — must not feed the comparison, or a stray `App.foo` there could mask a
  # real omission in the card below.
  def card(text) = text.split("# ---", 2).last.to_s

  # `App.<name>` tokens in the card; the first segment only, so `App.db.query` yields `db`. The name
  # class spans digits/caps so a future `oauth2` is compared whole, not silently truncated to `oauth`.
  def card_names(text) = scan(card(text), /(?<![\w.])App\.([a-zA-Z_][a-zA-Z0-9_]*[?!]?)/)

  # `App.db.<name>` tokens: the shortcuts on the db namespace.
  def card_db_names(text) = scan(card(text), /(?<![\w.])App\.db\.([a-zA-Z_][a-zA-Z0-9_]*[?!]?)/)

  def scan(text, pattern) = text.scan(pattern).flatten.map(&:to_sym).uniq.sort
end
