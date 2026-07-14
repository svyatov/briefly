# frozen_string_literal: true

module Briefly
  # An ordered list of facade-wide and global +rescue_from+ registrations, queried at dispatch time.
  # A shortcut's own handlers live on the {Briefly::Shortcut}, not here — this holds only the
  # unscoped handlers a single shortcut cannot voice.
  #
  # Entries are stored oldest-first and matched newest-first, so the most recent registration for a
  # given error class wins. Reads are lock-free against a frozen array; writes rebind it under a
  # mutex, because rebinding alone would drop concurrent registrations.
  class RescueRegistry
    # A single registration.
    Entry = Struct.new(:klass, :handler)

    def initialize
      @entries = [].freeze
      @mutex = Mutex.new
    end

    # @api private
    # @param klass [Class] matched against the raised error and its subclasses
    # @param handler [Proc] called with +(error, shortcut_name)+
    # @return [self]
    def add(klass, handler)
      @mutex.synchronize { @entries = [*@entries, Entry.new(klass, handler)].freeze }
      self
    end

    # @api private
    # @param error [Exception]
    # @return [Proc, nil] the most recently registered handler whose class matches +error+, or +nil+
    def handler_for(error) = @entries.reverse_each.find { |entry| error.is_a?(entry.klass) }&.handler

    # @api private
    # @return [Integer] how many registrations the registry holds
    def size = @entries.size

    # Drops every registration. Reach it as +Briefly.rescues.clear+ to reset globally registered
    # handlers between test examples, so a handler from one example cannot leak into the next.
    #
    # @return [self]
    def clear
      @mutex.synchronize { @entries = [].freeze }
      self
    end
  end
end
