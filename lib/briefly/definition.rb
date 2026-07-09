# frozen_string_literal: true

module Briefly
  # One shortcut declaration: its canonical name, its aliases, its body, and whether it memoizes.
  class Definition
    # @return [Symbol] the primary method name
    attr_reader :canonical

    # @return [Array<Symbol>] additional method names delegating to the same body and memo cell
    attr_reader :aliases

    # @return [Proc] the implementation, bound to the facade at call time
    attr_reader :body

    # @return [Symbol] the private singleton method the body compiles to
    attr_reader :raw_name

    # @param canonical [Symbol]
    # @param aliases [Array<Symbol>]
    # @param body [Proc]
    def initialize(canonical, aliases, body)
      @canonical = canonical
      @aliases = aliases
      @body = body
      @raw_name = :"#{Facade::BODY_PREFIX}#{canonical}"
      @memoized = false
    end

    # Builder copies the facade's definitions before mutating them, so an aborted pass cannot
    # leave the live facade half-configured. Hash#dup would share this array.
    #
    # @param other [Briefly::Definition]
    # @return [void]
    def initialize_copy(other)
      super
      @aliases = other.aliases.dup
    end

    # Marks the value as computed once and cached. A redeclared shortcut is a fresh, unmemoized
    # Definition, so there is no un-memoize.
    #
    # @return [void]
    def memoize! = @memoized = true

    # @return [Boolean]
    def memoized? = @memoized

    # @return [Array<Symbol>] canonical name followed by every alias
    def names = [@canonical, *@aliases]
  end
end
