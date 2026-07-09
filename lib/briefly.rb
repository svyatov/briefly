# frozen_string_literal: true

require "briefly/version"
require "briefly/errors"
require "briefly/definition"
require "briefly/error_registry"
require "briefly/facade"
require "briefly/builder"

# A terse, curated facade over an application's most frequently reached-for objects.
#
#   App = Briefly.new do
#     use Briefly::Rails
#     shortcut(:redis) { REDIS_POOL }
#   end
module Briefly
  autoload :Rails, "briefly/rails"

  @errors = ErrorRegistry.new

  class << self
    # Builds a facade. The block is +instance_eval+'d on a {Briefly::Builder}.
    #
    # @yield [] the shortcut declarations
    # @return [Briefly::Facade]
    def new(&) = Facade.new.configure(&)

    # Registers a handler that applies to every shortcut on every facade, consulted only after the
    # facade's own handlers. Takes no shortcut names.
    #
    # @param error_class [Class] matched against the raised error and its subclasses
    # @yield [error, shortcut_name] the recovery block; its return value becomes the shortcut's value
    # @return [self]
    def rescue_from(error_class, &handler)
      unless error_class.is_a?(Class)
        raise ArgumentError, "rescue_from expects the error class first, got #{error_class.inspect}"
      end
      raise ArgumentError, "rescue_from(#{error_class}) requires a block" unless handler

      @errors.add(error_class, nil, handler)
      self
    end

    # @return [Briefly::ErrorRegistry] the global registry
    attr_reader :errors
  end
end
