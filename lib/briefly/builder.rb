# frozen_string_literal: true

module Briefly
  # Receives the DSL. {Briefly.new}'s block and {Briefly::Facade#configure}'s block are
  # +instance_eval+'d here, never on the facade, so DSL verbs can never collide with shortcut names.
  #
  # The block only collects; {#compile!} then validates, and {Briefly::Facade#configure} installs.
  class Builder
    # @return [Briefly::Facade] the facade under construction, for packs that need lifecycle hooks
    attr_reader :facade

    # @api private
    # @param facade [Briefly::Facade]
    # @param defs [Hash{Symbol => Briefly::Definition}] copies of the facade's current definitions
    def initialize(facade, defs)
      @facade = facade
      @defs = defs
      @errors = []
    end

    # Applies a pack: any object responding to +#install(builder)+.
    #
    # @param pack [#install]
    # @return [self]
    def use(pack)
      pack.install(self)
      self
    end

    # Declares a shortcut. Redeclaring a name (canonical or alias) silently overrides it.
    #
    # @param canonical [Symbol] the primary method name; may end in +?+ or +!+
    # @param aliases [Array<Symbol>] extra names sharing the body and the memo cell
    # @yield the implementation, bound to the facade at call time
    # @return [Symbol] the canonical name
    # @raise [Briefly::ReservedNameError] if any name shadows a facade method
    def shortcut(canonical, *aliases, &body)
      raise ArgumentError, "shortcut(#{canonical.inspect}) requires a block" unless body

      defn = Definition.new(canonical, aliases, body)
      defn.names.each { |name| validate_name!(name) }
      purge(defn.names, except: canonical)
      @defs[canonical] = defn
      canonical
    end

    # Marks an already-declared shortcut as memoized: computed once, cached for the process lifetime.
    #
    # @param name [Symbol] a canonical name or an alias
    # @param opts [Hash] reserved for future use; none are accepted
    # @return [Symbol] the canonical name
    # @raise [Briefly::UnknownShortcutError] if +name+ does not resolve
    def memoize(name, **opts)
      raise ArgumentError, "memoize(#{name.inspect}) got unknown options: #{opts.keys.join(", ")}" unless opts.empty?

      defn = fetch(name)
      defn.memoize!
      defn.canonical
    end

    # Registers an error handler. The handler's return value becomes the shortcut's return value.
    #
    # Because +{}+ binds to the nearest token, +rescue_from StandardError { }+ is a call to a method
    # named +StandardError+. Use +rescue_from Err, :name do |e| ... end+ or +rescue_from(Err, :name) { |e| ... }+.
    #
    # @param error_class [Class] matched against the raised error and its subclasses
    # @param names [Array<Symbol>] shortcuts to scope to; none means facade-wide
    # @yield [error, shortcut_name] the recovery block
    # @return [self]
    def rescue_from(error_class, *names, &handler)
      unless error_class.is_a?(Class)
        raise ArgumentError, "rescue_from expects the error class first, e.g. rescue_from(StandardError, :name) { }"
      end
      raise ArgumentError, "rescue_from(#{error_class}) requires a block" unless handler

      scoped = names.flatten.map { |name| fetch(name).canonical }
      @errors << [error_class, (scoped.empty? ? nil : scoped), handler]
      self
    end

    # Validates everything collected in this pass. {Briefly::Facade#configure} installs the result.
    #
    # @api private
    # @return [Array] +[definitions, error_entries]+
    # @raise [Briefly::Error] if a memoized shortcut's body takes arguments
    def compile!
      @defs.each_value do |defn|
        # `parameters`, not `arity`: a `{ |&blk| }` body has arity 0 but its block would be dropped.
        next unless defn.memoized? && !defn.body.parameters.empty?

        raise Error, "cannot memoize #{defn.canonical}: its body takes arguments"
      end
      [@defs, @errors]
    end

    private

    def validate_name!(name)
      raise ArgumentError, "shortcut names must be Symbols, got #{name.inspect}" unless name.is_a?(Symbol)
      raise ReservedNameError, "#{name} is reserved by Briefly::Facade" if Facade::RESERVED.include?(name)
      return unless name.start_with?(Facade::BODY_PREFIX)

      raise ReservedNameError, "#{name} is reserved: #{Facade::BODY_PREFIX}* names hold compiled shortcut bodies"
    end

    # Frees the incoming names from any definition that currently owns them, so a redeclaration
    # never leaves a stale alias pointing at the old body.
    def purge(names, except:)
      @defs.delete_if { |canonical, _| canonical != except && names.include?(canonical) }
      @defs.each_value { |defn| defn.aliases.replace(defn.aliases - names) }
    end

    def fetch(name)
      defn = @defs[name] || @defs.each_value.find { |d| d.aliases.include?(name) }
      raise UnknownShortcutError, "unknown shortcut: #{name.inspect}" unless defn

      defn
    end
  end
end
