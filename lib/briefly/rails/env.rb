# frozen_string_literal: true

module Briefly
  module Rails
    # The environment and its predicates.
    #
    #   App = Briefly.define { use Briefly::Rails::Env }
    #   App.env           # => Rails.env
    #   App.production?   # => Rails.env.production?
    #
    # Inside this file the framework is always +::Rails+ — bare +Rails+ would resolve to the parent module.
    module Env
      module_function

      # @param builder [Briefly::Builder]
      # @return [Briefly::Builder]
      def install(builder)
        builder.shortcut(:env) { ::Rails.env }
        builder.shortcut(:production?) { ::Rails.env.production? }
        builder.shortcut(:development?) { ::Rails.env.development? }
        builder.shortcut(:test?) { ::Rails.env.test? }
        builder.shortcut(:local?) { ::Rails.env.local? }
        builder
      end
    end
  end
end
