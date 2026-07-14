# frozen_string_literal: true

require "test_helper"

class PackTest < BrieflyTest
  module LeafPack
    module_function

    def install(builder)
      builder.shortcut(:leaf) { :leaf }.memoize.rescue_from(StandardError) { :never }
    end
  end

  module ComposingPack
    module_function

    def install(builder)
      builder.use(LeafPack)
      builder.shortcut(:composed) { :composed }
    end
  end

  # A pack is any object responding to #install(builder); no mixin required.
  class LifecyclePack
    attr_reader :seen_facade

    def install(builder)
      @seen_facade = builder.facade
      builder.shortcut(:lifecycle) { :lifecycle }
    end
  end

  def test_use_installs_a_pack
    facade = Briefly.define { use LeafPack }

    assert_equal :leaf, facade.leaf
  end

  def test_a_pack_can_memoize
    facade = Briefly.define { use LeafPack }

    assert_equal [:leaf], memoized_names(facade)
  end

  def test_packs_compose
    facade = Briefly.define { use ComposingPack }

    assert_equal %i[composed leaf], facade.briefly.shortcuts
  end

  def test_use_returns_the_builder_so_packs_can_chain
    facade = Briefly.define { use(LeafPack).use(ComposingPack) }

    assert_equal %i[composed leaf], facade.briefly.shortcuts
  end

  def test_a_pack_receives_the_facade_for_lifecycle_wiring
    pack = LifecyclePack.new
    facade = Briefly.define { use pack }

    assert_same facade, pack.seen_facade
  end

  def test_an_app_can_override_a_pack_shortcut
    facade = Briefly.define do
      use LeafPack
      shortcut(:leaf) { :overridden }
    end

    assert_equal :overridden, facade.leaf
  end

  def test_a_pack_can_be_used_from_configure
    facade = Briefly.define
    facade.briefly.configure { use LeafPack }

    assert_equal :leaf, facade.leaf
  end
end
