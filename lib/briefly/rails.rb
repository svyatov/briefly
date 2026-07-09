# frozen_string_literal: true

require "briefly"
require "briefly/rails/reload"

module Briefly
  # Shortcut pack for Rails applications.
  #
  #   App = Briefly.new { use Briefly::Rails }
  #   App.c            # => Rails.configuration
  #   App.render(...)  # => ApplicationController.renderer.render(...)
  #
  # Nothing here memoizes. Every shortcut is a live lookup: the framework already caches the
  # expensive ones (+helpers+, +routes+, +renderer+) on objects it refreshes on reload, so caching
  # them again would only go stale.
  #
  # Inside this file the framework is always +::Rails+ — bare +Rails+ would resolve to this module.
  module Rails
    module_function

    # @param builder [Briefly::Builder]
    # @return [Briefly::Builder]
    def install(builder)
      builder.use(Reload)
      install_config(builder)
      install_env(builder)
      install_view(builder)
      builder
    end

    # @api private
    # @param builder [Briefly::Builder]
    # @return [void]
    def install_config(builder)
      builder.shortcut(:config, :c) { ::Rails.configuration }
      builder.shortcut(:config_x, :x) { ::Rails.configuration.x }
      builder.shortcut(:root) { ::Rails.root }
      builder.shortcut(:cache) { ::Rails.cache }
      builder.shortcut(:logger, :log) { ::Rails.logger }
      builder.shortcut(:credentials, :cred) { ::Rails.application.credentials }
    end

    # @api private
    # @param builder [Briefly::Builder]
    # @return [void]
    def install_env(builder)
      builder.shortcut(:env) { ::Rails.env }
      builder.shortcut(:production?) { ::Rails.env.production? }
      builder.shortcut(:development?) { ::Rails.env.development? }
      builder.shortcut(:test?) { ::Rails.env.test? }
      builder.shortcut(:local?) { ::Rails.env.local? }
    end

    # @api private
    # @param builder [Briefly::Builder]
    # @return [void]
    def install_view(builder)
      builder.shortcut(:helpers, :h) { ::ApplicationController.helpers }
      builder.shortcut(:routes, :r) { ::Rails.application.routes.url_helpers }
      builder.shortcut(:renderer) { ::ApplicationController.renderer }
      builder.shortcut(:render) { |*args, **kwargs, &blk| renderer.render(*args, **kwargs, &blk) }
    end

    private_class_method :install_config, :install_env, :install_view
  end
end
