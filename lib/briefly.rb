# frozen_string_literal: true

require "candor"

require "briefly/version"
require "briefly/errors"
require "briefly/definition"
require "briefly/error_registry"
require "briefly/facade"
require "briefly/builder"

# A terse, curated facade over an application's most frequently reached-for objects.
#
#   App = Briefly.define do
#     use Briefly::Rails
#     shortcut(:redis) { REDIS_POOL }
#   end
module Briefly
  autoload :Rails, "briefly/rails"

  @errors = ErrorRegistry.new

  # The packs this gem ships, under the short names +use+ accepts. Values are constant paths, never
  # constants: naming +Briefly::Rails::DB+ here would resolve it at load and defeat the autoload above.
  @packs = {
    "rails" => "Briefly::Rails",
    "rails/config" => "Briefly::Rails::Config",
    "rails/env" => "Briefly::Rails::Env",
    "rails/view" => "Briefly::Rails::View",
    "rails/db" => "Briefly::Rails::DB",
    "rails/reload" => "Briefly::Rails::Reload"
  }

  class << self
    # Builds a facade. The block is +instance_eval+'d on a {Briefly::Builder}.
    #
    # @yield [] the shortcut declarations
    # @return [Briefly::Facade]
    def define(&) = Facade.new.configure(&)

    # Registers a pack under a short name, so +use "myapp/redis"+ resolves it. Re-registering a name
    # overrides it. There is no inflection and no path guessing: this table is the only source of truth.
    #
    # @param name [String, Symbol] the short name
    # @param pack [#install, String] the pack, or a constant path resolved on first use
    # @return [self]
    def register(name, pack)
      @packs[name.to_s] = pack
      self
    end

    # Resolves a short name to a pack. A registered constant path is resolved here, not at registration,
    # so a pack's file loads only when something uses it.
    #
    # The path is walked one segment at a time rather than handed to +Object.const_get+ whole, so a
    # +NameError+ raised *inside* a pack's file as it autoloads propagates untouched. Rescuing around
    # the whole resolution would launder that bug into an {Briefly::UnknownPackError}.
    #
    # @param name [String, Symbol]
    # @return [#install]
    # @raise [Briefly::UnknownPackError] if +name+ is not registered, or names a path that does not resolve
    def pack(name)
      entry = @packs.fetch(name.to_s) { raise UnknownPackError, "unknown pack: #{name.inspect}" }
      return entry unless entry.is_a?(String)

      entry.split("::").reduce(Object) do |mod, segment|
        unless mod.const_defined?(segment, false)
          raise UnknownPackError, "pack #{name.inspect} names #{entry.inspect}, which does not resolve"
        end

        mod.const_get(segment, false)
      end
    end

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
