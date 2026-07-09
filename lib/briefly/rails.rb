# frozen_string_literal: true

require "briefly"
require "briefly/rails/db"
require "briefly/rails/reload"

module Briefly
  # Shortcut pack for Rails applications.
  #
  #   App = Briefly.define { use Briefly::Rails }
  #   App.c            # => Rails.configuration
  #   App.render(...)  # => ApplicationController.renderer.render(...)
  #   App.db.txn { }   # => ApplicationRecord.transaction { }
  #
  # An umbrella over {Config}, {Env}, {View} and {Reload}, plus {DB} under the +db+ namespace. Each is
  # a pack in its own right, so a facade can take only the parts it wants:
  #
  #   Admin = Briefly.define do
  #     use "rails/env"
  #     namespace(:primary) { use "rails/db" }
  #   end
  #
  # Nothing here memoizes. Every shortcut is a live lookup: the framework already caches the
  # expensive ones (+helpers+, +routes+, +renderer+) on objects it refreshes on reload, so caching
  # them again would only go stale. {Reload} is still wired in, because the *application's* own
  # memoized shortcuts need clearing; the mini-packs, having nothing to clear, leave it alone.
  #
  # Inside this file the framework is always +::Rails+ — bare +Rails+ would resolve to this module.
  module Rails
    module_function

    # @param builder [Briefly::Builder]
    # @return [Briefly::Builder]
    def install(builder)
      builder.use(Reload)
      builder.use(Config)
      builder.use(Env)
      builder.use(View)
      builder.namespace(:db) { use DB }
      builder
    end

    # Configuration, paths and the application-wide singletons.
    module Config
      module_function

      # @param builder [Briefly::Builder]
      # @return [Briefly::Builder]
      def install(builder)
        builder.shortcut(:config, :c) { ::Rails.configuration }
        builder.shortcut(:config_x, :x) { ::Rails.configuration.x }
        builder.shortcut(:root) { ::Rails.root }
        builder.shortcut(:cache) { ::Rails.cache }
        builder.shortcut(:logger, :log) { ::Rails.logger }
        builder.shortcut(:credentials, :cred) { ::Rails.application.credentials }
        builder
      end
    end

    # The environment and its predicates.
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

    # Helpers, routes and rendering outside a controller.
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
