# frozen_string_literal: true

module Briefly
  # Base class for every error raised by Briefly.
  class Error < StandardError; end

  # Raised when +memoize+ or +rescue_from+ names a shortcut that does not exist.
  class UnknownShortcutError < Error; end

  # Raised when a shortcut name or alias would shadow a facade method.
  class ReservedNameError < Error; end

  # Raised when +use+ names a pack that is not registered.
  class UnknownPackError < Error; end

  # Sentinel distinguishing "not memoized yet" from a memoized +nil+.
  UNSET = Object.new.freeze
end
