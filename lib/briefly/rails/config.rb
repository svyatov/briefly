# frozen_string_literal: true

module Briefly
  module Rails
    # Configuration, paths and the application-wide singletons.
    #
    #   App = Briefly.define { use Briefly::Rails::Config }
    #   App.c      # => Rails.configuration
    #   App.root   # => Rails.root
    #
    # +error+ is the framework's handled-error reporter: +App.error.report(e)+, +App.error.handle { }+.
    # +config_for+ reads a per-environment YAML config on every call, forwarding any keyword (such as
    # +env:+) to +::Rails.application.config_for+; it takes an argument and is therefore never memoized —
    # compose one that is with +memoize(:payments) { config_for(:payments) }+.
    #
    # Inside this file the framework is always +::Rails+ — bare +Rails+ would resolve to the parent module.
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
        builder.shortcut(:error) { ::Rails.error }
        builder.shortcut(:config_for) { |name, **opts| ::Rails.application.config_for(name, **opts) }
        builder
      end
    end
  end
end
