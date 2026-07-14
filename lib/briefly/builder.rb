# frozen_string_literal: true

module Briefly
  # Receives the DSL. {Briefly.define}'s block and {Briefly::Facade::Control#configure}'s block are
  # +instance_eval+'d here, never on the facade, so DSL verbs can never collide with shortcut names.
  #
  # The block only collects; {#compile!} then validates, and {Briefly::Facade::Control#configure} installs.
  class Builder
    # A validated {#compile!} pass, ready for a {Briefly::Facade} to install. +child_plans+ holds one
    # +[child_facade, child_plan]+ pair per namespace this pass collected, so +__commit+ can walk the
    # tree children first.
    Plan = Struct.new(:defs, :rescue_entries, :children, :child_plans)

    # @return [Briefly::Facade] the facade under construction, for packs that need lifecycle hooks
    attr_reader :facade

    # @api private
    # @param facade [Briefly::Facade]
    # @param defs [Hash{Symbol => Briefly::Shortcut}] copies of the facade's current shortcuts
    # @param children [Hash{Symbol => Briefly::Facade}] the facade's namespaces, by name
    def initialize(facade, defs, children)
      @facade = facade
      @defs = defs
      @children = children
      @rescues = []
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
    # the child's own DSL — +shortcut+ (and the shortcut it returns), +use+, +rescue_from+, and namespaces.
    #
    # The child is created once and reused by later passes, so its memos survive +configure+.
    # {Briefly::Facade::Control#clear_memos!} cascades into it. Two limits, both deliberate: a child body cannot
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
      # The proc above is a literal in this file. Point the compiled method at the caller's block instead.
      @defs[name].source_location = block.source_location
      @children[name] = child
      @pending[name] = pending
      name
    end

    # Declares a shortcut, or fetches an already-declared one to refine.
    #
    # With a block, declares the shortcut (redeclaring a name, canonical or alias, silently overrides it)
    # and returns the {Briefly::Shortcut}, so you can chain +.memoize+ or +.rescue_from+ onto it. With no
    # block, +shortcut(name)+ fetches the shortcut +name+ resolves to (canonical or alias) so a pack's
    # shortcut can be refined; it never declares, purges, or overrides.
    #
    # @param canonical [Symbol] the primary method name; may end in +?+ or +!+
    # @param aliases [Array<Symbol>] extra names sharing the body and the memo cell (declare only)
    # @yield the implementation, bound to the facade at call time
    # @return [Briefly::Shortcut] the declared or fetched shortcut, ready to refine
    # @raise [ArgumentError] if a bodiless call is given aliases — a fetch ignores them, so a
    #   non-empty list means the block was forgotten
    # @raise [Briefly::ReservedNameError] if any name shadows a facade method
    # @raise [Briefly::UnknownShortcutError] if a bodiless +name+ resolves to nothing
    def shortcut(canonical, *aliases, &body)
      unless body
        # A bodiless `shortcut(name)` fetches an existing shortcut to refine; aliases are meaningless
        # there, so a non-empty list means a block was forgotten — fail loudly, don't drop them silently.
        raise ArgumentError, "shortcut(#{canonical.inspect}, ...) with aliases requires a block" unless aliases.empty?

        return fetch(canonical)
      end

      defn = Shortcut.new(canonical, aliases, body, source_location_for(body))
      defn.names.each { |name| validate_name!(name) }
      purge(defn.names, except: canonical)
      @defs[canonical] = defn
    end

    # Registers a facade-wide error handler: one applying to every shortcut, consulted after each
    # shortcut's own handlers. The handler's return value becomes the shortcut's return value. To guard a
    # single shortcut, chain onto it instead — +shortcut(name).rescue_from(error_class) { ... }+ — which
    # is why this verb takes no shortcut names.
    #
    # Because +{}+ binds to the nearest token, +rescue_from StandardError { }+ is a call to a method
    # named +StandardError+. Use +rescue_from Err do |e| ... end+ or +rescue_from(Err) { |e| ... }+.
    #
    # @param error_class [Class] matched against the raised error and its subclasses
    # @param names [Array<Symbol>] must be empty; any name is refused because the shortcut expresses it
    # @yield [error, shortcut_name] the recovery block
    # @return [self]
    # @raise [ArgumentError] if any shortcut names are given
    def rescue_from(error_class, *names, &block)
      Briefly.send(:validate_rescue!, error_class, block)
      unless names.flatten.empty?
        raise ArgumentError, "rescue_from(#{error_class}) takes no shortcut names — scope one to its " \
                             "shortcut with shortcut(name).rescue_from(#{error_class}) { ... }, or omit " \
                             "names for a facade-wide handler"
      end

      @rescues << [error_class, block]
      self
    end

    # Validates everything collected in this pass, and recursively every namespace pass it collected.
    # {Briefly::Facade::Control#configure} installs the result. Validation of the whole tree finishes before any
    # of it is installed.
    #
    # @api private
    # @return [Briefly::Builder::Plan]
    # @raise [Briefly::Error] if a memoized shortcut's body takes arguments
    def compile!
      @defs.each_value do |defn|
        # `parameters`, not `arity`: a `{ |&blk| }` body has arity 0 but its block would be dropped.
        next unless defn.memoized? && !defn.body.parameters.empty?

        raise Error, "cannot memoize #{defn.canonical}: its body takes arguments"
      end
      Plan.new(@defs, @rescues, @children, @pending.map { |name, builder| [@children[name], builder.compile!] })
    end

    private

    # A `&:upcase`-style Proc carries no location of its own; fall back to the caller's declaration site
    # so the compiled method points at the user's code, never a fabricated file. `namespace` overwrites it
    # anyway. Depth 2 skips this helper and `shortcut` to land on the DSL block — or a pack's `install`.
    #
    # @param body [Proc]
    # @return [Array(String, Integer)]
    def source_location_for(body)
      body.source_location || caller_locations(2, 1).first.then { |l| [l.path, l.lineno] }
    end

    def validate_name!(name)
      raise ArgumentError, "shortcut names must be Symbols, got #{name.inspect}" unless name.is_a?(Symbol)
      raise ReservedNameError, "#{name} is reserved by Briefly::Facade" if Facade::RESERVED.include?(name)
      # Candor raises here too, but as an ArgumentError, and only once the pass is already committing.
      return unless name.start_with?(Candor::BODY_PREFIX)

      raise ReservedNameError, "#{name} is reserved: #{Candor::BODY_PREFIX}* names hold compiled shortcut bodies"
    end

    # Frees the incoming names from any shortcut that currently owns them, so a redeclaration
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
