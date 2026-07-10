# frozen_string_literal: true

require "monitor"

module Briefly
  # The object returned by {Briefly.define}. Shortcuts are compiled onto its singleton class as real
  # methods, so +respond_to?+, console tab-completion and test stubbing all work unaided.
  #
  # Memo store: reads are lock-free against a frozen snapshot hash; writes swap in a new frozen hash
  # under a reentrant +Monitor+, because a memoized body may call another memoized shortcut.
  class Facade
    def initialize
      @__defs = {}
      @__aliases = {}
      @__memos = {}.freeze
      @__monitor = Monitor.new
      @__errors = ErrorRegistry.new
      @__public = [].freeze
      @__children = {}
    end

    # @return [Array<Symbol>] canonical shortcut names, sorted; aliases excluded
    def shortcuts = @__defs.keys.sort

    # @param name [Symbol] a canonical name or an alias
    # @return [Boolean]
    def shortcut?(name) = @__defs.key?(name) || @__aliases.key?(name)

    # Drops every memoized value, here and in every namespace. Thread-safe.
    #
    # @return [self]
    def clear_memos!
      @__monitor.synchronize { @__memos = {}.freeze }
      # Each namespace owns its memo store and its own lock, so a child clears outside our monitor.
      # One `Reload` on the root therefore clears the whole tree, including namespaces holding no pack.
      @__children.each_value(&:clear_memos!)
      self
    end
    alias reset! clear_memos!

    # Reopens the facade for another builder pass and recompiles. The builder starts from copies of the
    # current definitions, so a pass that raises leaves the live facade — and every namespace under it
    # — untouched.
    #
    # @yield [] evaluated against a {Briefly::Builder}
    # @return [self]
    def configure(&block)
      builder = __prepare
      builder.instance_eval(&block) if block
      # `compile!` validates the whole tree before `__commit` installs any of it. Splitting the two is
      # what keeps a namespace pass atomic: `Builder#namespace` collects its child's pass rather than
      # running it, so a later failure anywhere cannot leave an already-reachable child half-updated.
      __commit(builder.compile!)
      self
    end

    # @return [String] a summary listing shortcut names; never dumps memo internals
    def inspect = "#<#{self.class.name} shortcuts=#{shortcuts.inspect}>"
    alias to_s inspect

    private

    # A builder seeded with copies of everything a pass may mutate. {Briefly::Builder#namespace} calls
    # this on the child it collects.
    #
    # @return [Briefly::Builder]
    def __prepare = Builder.new(self, @__defs.transform_values(&:dup), @__children.dup)

    # Installs a validated pass, children first. Nothing here may raise: every check ran in +compile!+.
    #
    # @param plan [Array] +compile!+'s +[defs, error_entries, children, child_plans]+
    # @return [self]
    def __commit(plan)
      defs, error_entries, children, child_plans = plan
      child_plans.each { |child, child_plan| child.send(:__commit, child_plan) }
      @__children = children
      __install(defs, error_entries)
    end

    # Compiles definitions onto the singleton class and appends error registrations.
    def __install(defs, error_entries)
      wanted = defs.each_value.flat_map(&:names)
      __remove_methods(@__public - wanted)
      defs.each_value { |defn| __define(defn) }

      @__public = wanted.freeze
      @__defs = defs
      @__aliases = defs.each_value.flat_map { |d| d.aliases.map { |a| [a, d.canonical] } }.to_h
      error_entries.each { |klass, names, handler| @__errors.add(klass, names, handler) }
      self
    end

    def __remove_methods(names)
      names.each { |name| singleton_class.send(:remove_method, name) }
    end

    # Candor installs the body privately under its reserved prefix, reads that *compiled* method's
    # `parameters` — never `defn.body.parameters`, which reports every positional as `:opt` and would
    # silently destroy arity strictness — and compiles a dispatch of the same arity onto every name.
    # Arity is enforced there, before `__call` and its rescue layer are entered.
    #
    # No `parameters:` override for a memoized shortcut: `compile!` has already refused any memoized body
    # that takes an argument, so its compiled shape is empty and `App.catalog(1)` raises on its own.
    #
    # `source_location:` because `namespace` rewrites it: its body is a `proc { child }` literal in
    # `builder.rb`, and the compiled method must point at the caller's block instead.
    def __define(defn)
      Candor.define(singleton_class, defn.canonical,
                    aliases: defn.aliases,
                    via: :__call,
                    source_location: defn.source_location,
                    body: defn.body)
    end

    def __call(name, ...)
      # Outside the rescue: an internal KeyError must never be laundered into a user's fallback.
      defn = @__defs.fetch(name)
      begin
        return __memo(name) { send(defn.raw_name) } if defn.memoized?

        send(defn.raw_name, ...)
      rescue StandardError => e
        __handle(e, name)
      end
    end

    def __memo(name)
      value = @__memos.fetch(name, UNSET)
      return value unless UNSET.equal?(value)

      # One reentrant lock for the whole facade: first computations of unrelated memoized shortcuts
      # serialize. Per-shortcut locks would deadlock on a body that reaches another memoized body.
      @__monitor.synchronize do
        value = @__memos.fetch(name, UNSET)
        return value unless UNSET.equal?(value)

        computed = yield # raising here stores nothing: a rescued fallback is never memoized
        @__memos = @__memos.merge(name => computed).freeze
        computed
      end
    end

    def __handle(error, name)
      entry = @__errors.scoped(name).find { |e| error.is_a?(e.klass) } ||
              @__errors.wide.find { |e| error.is_a?(e.klass) } ||
              Briefly.errors.wide.find { |e| error.is_a?(e.klass) }
      # Kernel.raise, not bare raise: a shortcut may not be named `raise`, but a pack could still
      # define one on a subclass, and this must never dispatch back into the facade.
      Kernel.raise(error) unless entry

      entry.handler.call(error, name)
    end
  end

  # Names a shortcut may not take: every facade method, plus Briefly's own private ones, plus the
  # Kernel private methods the facade itself calls with an implicit receiver. Other Kernel privates
  # (+puts+, +format+, ...) are deliberately absent: shadowing those is the user's call.
  Facade::RESERVED = (Facade.instance_methods + Facade.private_instance_methods(false) + %i[raise]).freeze
end
