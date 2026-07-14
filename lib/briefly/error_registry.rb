# frozen_string_literal: true

module Briefly
  # An ordered list of facade-wide and global +rescue_from+ registrations, queried at dispatch time.
  # A shortcut's own handlers live on the {Briefly::Shortcut}, not here — this holds only the
  # unscoped handlers a single shortcut cannot voice.
  #
  # Entries are stored oldest-first and returned newest-first, so the most recent registration for a
  # given error class wins. Reads are lock-free against a frozen array; writes rebind it under a
  # mutex, because rebinding alone would drop concurrent registrations.
  class ErrorRegistry
    # A single registration.
    Entry = Struct.new(:klass, :handler)

    def initialize
      @entries = [].freeze
      @mutex = Mutex.new
    end

    # @param klass [Class] matched against the raised error and its subclasses
    # @param handler [Proc] called with +(error, shortcut_name)+
    # @return [self]
    def add(klass, handler)
      @mutex.synchronize { @entries = [*@entries, Entry.new(klass, handler)].freeze }
      self
    end

    # @return [Enumerator<Entry>] every registration, most recently registered first
    def wide = @entries.reverse_each

    # @param error [Exception]
    # @return [Proc, nil] the most recently registered handler whose class matches +error+, or +nil+
    def handler_for(error) = wide.find { |entry| error.is_a?(entry.klass) }&.handler

    # @return [self]
    def clear
      @mutex.synchronize { @entries = [].freeze }
      self
    end
  end
end
