# frozen_string_literal: true

require "monitor"

module Briefly
  # The object returned by {Briefly.new}. Shortcuts are compiled onto its singleton class as real
  # methods, so +respond_to?+, console tab-completion and test stubbing all work unaided.
  #
  # Memo store: reads are lock-free against a frozen snapshot hash; writes swap in a new frozen hash
  # under a reentrant +Monitor+, because a memoized body may call another memoized shortcut.
  class Facade
    # Prefix of the private singleton methods holding compiled shortcut bodies. Shortcut names may
    # not start with it, or one shortcut would silently overwrite another's body.
    BODY_PREFIX = "__briefly_body_"

    def initialize
      @__defs = {}
      @__aliases = {}
      @__memos = {}.freeze
      @__monitor = Monitor.new
      @__errors = ErrorRegistry.new
      @__public = [].freeze
    end

    # @return [Array<Symbol>] canonical shortcut names, sorted; aliases excluded
    def shortcuts = @__defs.keys.sort

    # @param name [Symbol] a canonical name or an alias
    # @return [Boolean]
    def shortcut?(name) = @__defs.key?(name) || @__aliases.key?(name)

    # Drops every memoized value. Thread-safe.
    #
    # @return [self]
    def clear_memos!
      @__monitor.synchronize { @__memos = {}.freeze }
      self
    end
    alias reset! clear_memos!

    # Reopens the facade for another builder pass and recompiles. The builder starts from copies of
    # the current definitions, so a pass that raises leaves the live facade untouched.
    #
    # @yield [] evaluated against a {Briefly::Builder}
    # @return [self]
    def configure(&block)
      builder = Builder.new(self, @__defs.transform_values(&:dup))
      builder.instance_eval(&block) if block
      defs, error_entries = builder.compile!
      __install(defs, error_entries)
      self
    end

    # @return [String] a summary listing shortcut names; never dumps memo internals
    def inspect = "#<#{self.class.name} shortcuts=#{shortcuts.inspect}>"
    alias to_s inspect

    private

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

    def __define(defn)
      sc = singleton_class
      own = sc.private_instance_methods(false)
      sc.send(:remove_method, defn.raw_name) if own.include?(defn.raw_name)
      sc.define_method(defn.raw_name, &defn.body)
      sc.send(:private, defn.raw_name)

      canonical = defn.canonical
      dispatch = if defn.memoized?
                   # No parameters: `define_method` makes arity strict, so a memoized shortcut says
                   # so with an ArgumentError instead of silently returning the cache.
                   proc { __call(canonical) }
                 else
                   proc { |*args, **kwargs, &blk| __call(canonical, *args, **kwargs, &blk) }
                 end

      defn.names.each do |name|
        sc.send(:remove_method, name) if @__public.include?(name)
        sc.define_method(name, &dispatch)
      end
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
