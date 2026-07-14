# frozen_string_literal: true

module Briefly
  # One shortcut — and the object {Briefly::Builder#shortcut} hands back so you can refine it. A
  # declaration's memoization and its scoped error handlers both live here, on the shortcut itself, so
  # refining after a redeclaration affects the declaration you named, exactly as its body and aliases do.
  #
  #   shortcut(:catalog) { Catalog.load }.memoize
  #   shortcut(:redis) { REDIS_POOL }.rescue_from(Redis::BaseError) { nil }
  #
  # The name, aliases, body and location are internal; {#memoize} and {#rescue_from} are its public
  # refinement surface. It holds no {Briefly::Builder} reference — both refinements are self-contained.
  class Shortcut
    # @return [Symbol] the primary method name
    attr_reader :canonical

    # @return [Array<Symbol>] additional method names delegating to the same body and memo cell
    attr_reader :aliases

    # @return [Proc] the implementation, bound to the facade at call time
    attr_reader :body

    # @return [Symbol] the private singleton method the body compiles to
    attr_reader :raw_name

    # @return [Array<Array(Class, Proc)>] this shortcut's own error handlers, oldest first
    attr_reader :rescues

    # The +[file, line]+ the compiled methods report. {Briefly::Builder#shortcut} resolves it — the body's
    # own location, or the +shortcut+ call site for a location-less Proc like +&:upcase+ — and
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
      @rescues = []
      @source_location = source_location
    end

    # Builder copies the facade's shortcuts before mutating them, so an aborted pass cannot leave the
    # live facade half-configured. Hash#dup would share these arrays.
    #
    # @param other [Briefly::Shortcut]
    # @return [void]
    def initialize_copy(other)
      super
      @aliases = other.aliases.dup
      @rescues = other.rescues.dup
    end

    # Memoizes the value: computed once, cached for the process lifetime. A body that takes any
    # argument is refused at build time (in {Briefly::Builder#compile!}); the compiled method takes none.
    #
    # @return [self]
    def memoize
      @memoized = true
      self
    end

    # @return [Boolean]
    def memoized? = @memoized

    # Registers an error handler scoped to this shortcut. The handler's return value becomes the
    # shortcut's value; it is +call+ed with +(error, shortcut_name)+, never bound to the facade. Later
    # registrations for the same error class win.
    #
    # @param error_class [Class] matched against the raised error and its subclasses
    # @yield [error, shortcut_name] the recovery block
    # @return [self]
    def rescue_from(error_class, &handler)
      Briefly.send(:validate_rescue!, error_class, handler)
      @rescues << [error_class, handler]
      self
    end

    # @param error [Exception]
    # @return [Proc, nil] this shortcut's most recently registered handler whose class matches, or +nil+
    def handler_for(error) = @rescues.reverse_each.find { |klass, _| error.is_a?(klass) }&.last

    # @return [Array<Symbol>] canonical name followed by every alias
    def names = [@canonical, *@aliases]
  end
end
