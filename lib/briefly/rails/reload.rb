# frozen_string_literal: true

module Briefly
  module Rails
    # Lifecycle pack: clears the facade's memos at boot and on every code reload.
    #
    # Usable on its own, for a facade that has no framework shortcuts but does memoize objects
    # holding on to reloadable application classes:
    #
    #   Admin = Briefly.define { use Briefly::Rails::Reload }
    #
    # The callback holds the facade for the process lifetime and cannot be deregistered. Install it
    # on long-lived facades assigned to constants, not on facades built per request.
    module Reload
      # Marks a facade so a second +configure+ pass does not register a duplicate callback.
      INSTALLED = :@__briefly_rails_reload
      private_constant :INSTALLED

      module_function

      # @param builder [Briefly::Builder]
      # @return [Briefly::Builder]
      # @raise [Briefly::Error] outside a booted application
      def install(builder)
        facade = builder.facade
        return builder if facade.instance_variable_defined?(INSTALLED)

        app = ::Rails.application if defined?(::Rails)
        unless app.respond_to?(:reloader)
          raise Briefly::Error, "Briefly::Rails::Reload needs a booted application; use it from an initializer"
        end

        facade.instance_variable_set(INSTALLED, true)
        app.reloader.to_prepare { facade.briefly.clear_memos! }
        builder
      end
    end
  end
end
