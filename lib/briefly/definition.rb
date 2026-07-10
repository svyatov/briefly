# frozen_string_literal: true

module Briefly
  # One shortcut declaration: its canonical name, its aliases, its body, and whether it memoizes.
  #
  # @api private
  class Definition
    # @return [Symbol] the primary method name
    attr_reader :canonical

    # @return [Array<Symbol>] additional method names delegating to the same body and memo cell
    attr_reader :aliases

    # @return [Proc] the implementation, bound to the facade at call time
    attr_reader :body

    # @return [Symbol] the private singleton method the body compiles to
    attr_reader :raw_name

    # The +[file, line]+ the compiled methods report. {Briefly::Builder#shortcut} resolves it — the body's
    # own location, or the +shortcut+ call site for a bodiless-of-location Proc like +&:upcase+ — and
    # {Briefly::Builder#namespace} overwrites it: its child-returning proc literal lives in +builder.rb+,
    # and a namespace that pointed there would reintroduce, for namespaces, the lie this field exists to
    # remove.
    #
    # @return [Array(String, Integer)]
    attr_accessor :source_location

    # @param canonical [Symbol]
    # @param aliases [Array<Symbol>]
    # @param body [Proc]
    # @param source_location [Array(String, Integer)]
    def initialize(canonical, aliases, body, source_location)
      @canonical = canonical
      @aliases = aliases
      @body = body
      @raw_name = Candor.body_name(canonical)
      @memoized = false
      @source_location = source_location
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
