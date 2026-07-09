# frozen_string_literal: true

module Briefly
  # An ordered list of +rescue_from+ registrations, queried at dispatch time.
  #
  # Entries are stored oldest-first and returned newest-first, so the most recent registration for a
  # given error class wins. Reads are lock-free against a frozen array; writes rebind it under a
  # mutex, because rebinding alone would drop concurrent registrations.
  class ErrorRegistry
    # A single registration. +names+ is +nil+ for facade-wide/global handlers.
    Entry = Struct.new(:klass, :names, :handler)

    def initialize
      @entries = [].freeze
      @mutex = Mutex.new
    end

    # @param klass [Class] matched against the raised error and its subclasses
    # @param names [Array<Symbol>, nil] canonical shortcut names, or +nil+ for every shortcut
    # @param handler [Proc] called with +(error, shortcut_name)+
    # @return [self]
    def add(klass, names, handler)
      @mutex.synchronize { @entries = [*@entries, Entry.new(klass, names&.freeze, handler)].freeze }
      self
    end

    # @param name [Symbol] a canonical shortcut name
    # @return [Array<Entry>] handlers scoped to +name+, most recently registered first
    def scoped(name) = @entries.reverse_each.select { |entry| entry.names&.include?(name) }

    # @return [Array<Entry>] handlers scoped to no shortcut in particular, most recent first
    def wide = @entries.reverse_each.select { |entry| entry.names.nil? }

    # @return [self]
    def clear
      @mutex.synchronize { @entries = [].freeze }
      self
    end
  end
end
