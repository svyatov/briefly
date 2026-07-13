# frozen_string_literal: true

require "briefly"
require "briefly/rails/config"
require "briefly/rails/env"
require "briefly/rails/view"
require "briefly/rails/db"
require "briefly/rails/instrument"
require "briefly/rails/reload"

module Briefly
  # Shortcut pack for Rails applications.
  #
  #   App = Briefly.define { use Briefly::Rails }
  #   App.c            # => Rails.configuration
  #   App.render(...)  # => ApplicationController.renderer.render(...)
  #   App.db.txn { }   # => ApplicationRecord.transaction { }
  #
  # An umbrella over {Config}, {Env}, {View}, {Instrument} and {Reload}, plus {DB} under the +db+
  # namespace. Each is a pack in its own right, so a facade can take only the parts it wants:
  #
  #   Admin = Briefly.define do
  #     use "rails/env"
  #     namespace(:primary) { use "rails/db" }
  #   end
  #
  # Nothing here memoizes. Every shortcut is a live lookup: the framework already caches the
  # expensive ones (+helpers+, +routes+, +renderer+) on objects it refreshes on reload, so caching
  # them again would only go stale. {Reload} is still wired in, because the *application's* own
  # memoized shortcuts need clearing; the mini-packs, having nothing to clear, leave it alone.
  #
  # Inside this file the framework is always +::Rails+ — bare +Rails+ would resolve to this module.
  module Rails
    module_function

    # @param builder [Briefly::Builder]
    # @return [Briefly::Builder]
    def install(builder)
      builder.use(Reload)
      builder.use(Config)
      builder.use(Env)
      builder.use(View)
      builder.use(Instrument)
      builder.namespace(:db) { use DB }
      builder
    end
  end
end
