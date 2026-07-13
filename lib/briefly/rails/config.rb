# frozen_string_literal: true

module Briefly
  module Rails
    # Configuration, paths and the application-wide singletons.
    #
    #   App = Briefly.define { use Briefly::Rails::Config }
    #   App.c      # => Rails.configuration
    #   App.root   # => Rails.root
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
        builder
      end
    end
  end
end
