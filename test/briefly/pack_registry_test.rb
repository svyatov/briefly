# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class PackRegistryTest < BrieflyTest
  module NamedPack
    module_function

    def install(builder)
      builder.shortcut(:named) { :named }
      builder
    end
  end

  module OptionPack
    module_function

    def install(builder, greeting: "hi")
      builder.shortcut(:greeting) { greeting }
      builder
    end
  end

  def teardown
    packs.delete("test/named")
    super
  end

  def test_a_registered_pack_is_used_by_name
    Briefly.register("test/named", NamedPack)

    assert_equal :named, Briefly.new { use "test/named" }.named
  end

  def test_a_name_may_be_a_symbol
    Briefly.register(:"test/named", NamedPack)

    assert_equal :named, Briefly.new { use :"test/named" }.named
  end

  def test_register_returns_the_module_so_it_chains
    assert_same Briefly, Briefly.register("test/named", NamedPack)
  end

  def test_re_registering_a_name_overrides_it
    Briefly.register("test/named", NamedPack)
    Briefly.register("test/named", OptionPack)

    assert_equal "hi", Briefly.new { use "test/named" }.greeting
  end

  def test_an_unknown_name_raises
    error = assert_raises(Briefly::UnknownPackError) { Briefly.new { use "test/nope" } }

    assert_match(%r{unknown pack: "test/nope"}, error.message)
  end

  def test_a_registered_constant_path_resolves_on_use
    Briefly.register("test/named", "PackRegistryTest::NamedPack")

    assert_same NamedPack, Briefly.pack("test/named")
  end

  def test_a_registered_path_that_does_not_resolve_raises
    Briefly.register("test/named", "PackRegistryTest::Nope")

    error = assert_raises(Briefly::UnknownPackError) { Briefly.pack("test/named") }

    assert_match(/names "PackRegistryTest::Nope", which does not resolve/, error.message)
  end

  # `pack` walks the path a segment at a time rather than rescuing around `Object.const_get(path)`.
  # A blanket `rescue NameError` would launder a typo *inside* a pack's own file into an
  # UnknownPackError, hiding the real bug — the same trap `Facade#__call` avoids.
  def test_a_name_error_raised_inside_a_pack_is_not_laundered
    file = File.join(Dir.tmpdir, "briefly_exploding_pack_#{Process.pid}.rb")
    File.write(file, "module ExplodingPack; ThisConstantDoesNotExist; end\n")
    Object.autoload(:ExplodingPack, file)
    Briefly.register("test/named", "ExplodingPack")

    error = assert_raises(NameError) { Briefly.pack("test/named") }

    refute_kind_of Briefly::Error, error
    assert_match(/ThisConstantDoesNotExist/, error.message)
  ensure
    File.delete(file) if file && File.exist?(file)
    # The module body opened before it raised, so the constant outlives the failed autoload.
    Object.send(:remove_const, :ExplodingPack) if Object.const_defined?(:ExplodingPack, false)
  end

  def test_a_shipped_name_resolves_to_its_pack
    assert_same Briefly::Rails, Briefly.pack("rails")
    assert_same Briefly::Rails::DB, Briefly.pack("rails/db")
    assert_same Briefly::Rails::Reload, Briefly.pack("rails/reload")
  end

  # Naming the constants here would resolve them at load and defeat `autoload :Rails`.
  def test_every_shipped_pack_is_registered_as_a_constant_path
    shipped = packs.reject { |name, _| name.start_with?("test/") }

    refute_empty shipped
    shipped.each do |name, entry|
      assert_kind_of String, entry, "#{name}: must be a constant path, not a resolved constant"
    end
  end

  def test_a_pack_takes_options
    facade = Briefly.new { use OptionPack, greeting: "hello" }

    assert_equal "hello", facade.greeting
  end

  def test_a_named_pack_takes_options
    Briefly.register("test/named", OptionPack)
    facade = Briefly.new { use "test/named", greeting: "hello" }

    assert_equal "hello", facade.greeting
  end

  # Ruby drops an empty `**` splat, so `install(builder)` never sees the keyword.
  def test_a_pack_that_takes_no_options_still_installs
    facade = Briefly.new { use NamedPack }

    assert_equal :named, facade.named
  end

  private

  def packs = Briefly.instance_variable_get(:@packs)
end
