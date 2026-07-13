# frozen_string_literal: true

module Briefly
  module Rails
    # ActiveSupport::Notifications instrumentation, as a one-shortcut pack.
    #
    #   App = Briefly.define { use Briefly::Rails::Instrument }
    #   App.instrument("sql.query", model: "User") { run_the_query }
    #
    # A lean worker can +use "rails/instrument"+ on its own; the umbrella +use "rails"+ pulls it in too.
    # +payload+ is an optional trailing hash, so +instrument("evt", key: 1) { }+ threads +{ key: 1 }+
    # through to the subscribers, and the block's return value is preserved.
    #
    # +::ActiveSupport+ is fully qualified to match the sibling packs' +::Rails+ discipline; unlike
    # +Rails+ under +Briefly::Rails+, nothing here shadows the name, so it is style, not necessity.
    module Instrument
      module_function

      # @param builder [Briefly::Builder]
      # @return [Briefly::Builder]
      def install(builder)
        builder.shortcut(:instrument) do |name, payload = {}, &blk|
          ::ActiveSupport::Notifications.instrument(name, payload, &blk)
        end
        builder
      end
    end
  end
end
