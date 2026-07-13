# frozen_string_literal: true

require "rails/generators/base"

module Briefly
  # Namespace for briefly's Rails generators, discovered by `rails generate`.
  module Generators
    # Writes +config/initializers/briefly.rb+: a working +Briefly.define { use "rails" }+ facade plus a
    # commented, concern-grouped map of every shortcut the +rails+ pack installs. Re-run it to update —
    # Rails prompts before overwriting, so the map refreshes after a gem upgrade.
    #
    #   rails generate briefly:install          # => App    = Briefly.define { use "rails" }
    #   rails generate briefly:install Facade   # => Facade = Briefly.define { use "rails" }
    #
    # +::Rails+ is fully qualified throughout: a bare +Rails+ here would resolve to {Briefly::Rails},
    # the pack, not the framework. There is deliberately no +sig/+ entry: generators load only under
    # railties, outside the gem's typed runtime surface.
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      argument :name, type: :string, default: "App", banner: "ConstantName"

      # @return [void]
      def create_initializer
        template "briefly.rb.tt", "config/initializers/briefly.rb"
      end
    end
  end
end
