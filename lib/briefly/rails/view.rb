# frozen_string_literal: true

module Briefly
  module Rails
    # Helpers, routes and rendering outside a controller.
    #
    #   App = Briefly.define { use Briefly::Rails::View }
    #   App.h             # => ApplicationController.helpers
    #   App.render(...)   # => ApplicationController.renderer.render(...)
    #
    # Inside this file the framework is always +::Rails+ / +::ApplicationController+ — the bare names
    # would resolve to the parent module.
    module View
      module_function

      # @param builder [Briefly::Builder]
      # @return [Briefly::Builder]
      def install(builder)
        builder.shortcut(:helpers, :h) { ::ApplicationController.helpers }
        builder.shortcut(:routes, :r) { ::Rails.application.routes.url_helpers }
        builder.shortcut(:renderer) { ::ApplicationController.renderer }
        builder.shortcut(:render) { |*args, **kwargs, &blk| renderer.render(*args, **kwargs, &blk) }
        builder
      end
    end
  end
end
