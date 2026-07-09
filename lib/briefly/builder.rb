# frozen_string_literal: true

module Briefly
  # Receives the DSL. {Briefly.define}'s block and {Briefly::Facade#configure}'s block are
  # +instance_eval+'d here, never on the facade, so DSL verbs can never collide with shortcut names.
  #
  # The block only collects; {#compile!} then validates, and {Briefly::Facade#configure} installs.
  class Builder
    # @return [Briefly::Facade] the facade under construction, for packs that need lifecycle hooks
    attr_reader :facade

    # @api private
    # @param facade [Briefly::Facade]
    # @param defs [Hash{Symbol => Briefly::Definition}] copies of the facade's current definitions
    # @param children [Hash{Symbol => Briefly::Facade}] the facade's namespaces, by name
    def initialize(facade, defs, children)
      @facade = facade
      @defs = defs
      @children = children
      @errors = []
      @pending = {}
    end

    # Applies a pack: any object responding to +#install(builder)+, or a name {Briefly.register}'d for
    # one. Any keywords are forwarded to the pack's +install+. Ruby drops an empty +**+ splat, so a
    # pack taking no options needs no keyword parameter.
    #
    #   use Briefly::Rails::DB, base: "SecondaryApplicationRecord"
    #   use "rails/db", base: "SecondaryApplicationRecord"
    #
    # @param pack [#install, String, Symbol]
    # @return [self]
    # @raise [Briefly::UnknownPackError] if +pack+ is a name that is not registered
    def use(pack, **)
      pack = Briefly.pack(pack) unless pack.respond_to?(:install)
      pack.install(self, **)
      self
    end

    # Declares a namespace: a shortcut returning a child facade, so +App.db.query+ works. The block is
    # the child's own DSL — +shortcut+, +memoize+, +use+, +rescue_from+, and further namespaces.
    #
    # The child is created once and reused by later passes, so its memos survive +configure+.
    # {Briefly::Facade#clear_memos!} cascades into it. Two limits, both deliberate: a child body cannot
    # reach a root shortcut by bare name, and a root +rescue_from+ does not scope into the child.
    #
    # The child's pass is *collected*, not run: its builder is held until {#compile!} has validated the
    # whole tree, so a later failure in this pass cannot leave an already-reachable child mutated. One
    # builder per name, so a second +namespace(:db)+ in the same pass extends the first rather than
    # replacing it.
    #
    # @param name [Symbol] the shortcut the child answers to
    # @yield [] evaluated against the child's {Briefly::Builder}
    # @return [Symbol] +name+
    # @raise [Briefly::ReservedNameError] if +name+ shadows a facade method
    def namespace(name, &block)
      raise ArgumentError, "namespace(#{name.inspect}) requires a block" unless block

      validate_name!(name)
      child = @children[name] || Facade.new
      pending = @pending[name] || child.send(:__prepare)
      pending.instance_eval(&block)
      # Routes through `shortcut` for purge and validation, which drops the child this call just
      # resolved — so re-register both afterwards. An external `shortcut(name)` gets no such reprieve.
      shortcut(name) { child }
      @children[name] = child
      @pending[name] = pending
      name
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

    # Validates everything collected in this pass, and recursively every namespace pass it collected.
    # {Briefly::Facade#configure} installs the result. Validation of the whole tree finishes before any
    # of it is installed.
    #
    # @api private
    # @return [Array] +[definitions, error_entries, children, child_plans]+
    # @raise [Briefly::Error] if a memoized shortcut's body takes arguments
    def compile!
      @defs.each_value do |defn|
        # `parameters`, not `arity`: a `{ |&blk| }` body has arity 0 but its block would be dropped.
        next unless defn.memoized? && !defn.body.parameters.empty?

        raise Error, "cannot memoize #{defn.canonical}: its body takes arguments"
      end
      [@defs, @errors, @children, @pending.map { |name, builder| [@children[name], builder.compile!] }]
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
      # A namespace is just a shortcut returning its child, so redeclaring the name — as a canonical or
      # as someone else's alias — must drop the child too. Keeping it would leave `clear_memos!` walking
      # a facade nothing can reach. `except` gets no exemption: `namespace` re-registers its own child.
      @children.delete_if { |name, _| names.include?(name) }
      @pending.delete_if { |name, _| names.include?(name) }
    end

    def fetch(name)
      defn = @defs[name] || @defs.each_value.find { |d| d.aliases.include?(name) }
      raise UnknownShortcutError, "unknown shortcut: #{name.inspect}" unless defn

      defn
    end
  end
end
