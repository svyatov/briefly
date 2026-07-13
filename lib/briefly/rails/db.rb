# frozen_string_literal: true

module Briefly
  module Rails
    # Shortcut pack for a single database, reached through one Active Record class.
    #
    #   App = Briefly.define do
    #     namespace(:db)  { use Briefly::Rails::DB }
    #     namespace(:db2) { use Briefly::Rails::DB, base: "SecondaryApplicationRecord" }
    #   end
    #
    #   App.db.txn { App.db.query("select * from users where id = ?", 1) }
    #
    # +base+ is a constant path, resolved on every call. Pass a String, not the class: a pack is
    # +use+d from an initializer, where naming an autoloadable constant is what Rails warns about, and
    # the captured class would go stale on the first code reload — permanently, since {Reload} clears
    # memos, not closures. A Module is accepted for applications outside the autoloader, with that caveat.
    #
    # Nothing here memoizes: a connection is leased from the pool, and +query+ takes arguments. So the
    # pack does not wire {Reload}, and works without a booted application.
    #
    # +connected_to+ forwards every argument to +base.connected_to+ — +role:+, +shard:+, +prevent_writes:+,
    # and any custom role — so the full Rails multi-database surface is reachable. +reading+ and +writing+
    # are sugar for the two common roles; they forward the rest (+shard:+, +prevent_writes:+) but pin the
    # role, so +reading(role: :writing)+ still reads. Rails only allows +connected_to+ on +ActiveRecord::Base+
    # or an abstract class — the one that declared +connects_to+ — so +base+ must be such a class; on a
    # concrete model it raises +NotImplementedError+.
    #
    # Inside this file the framework is always +::Rails+ — bare +Rails+ would resolve to the parent module.
    module DB
      module_function

      # @param builder [Briefly::Builder]
      # @param base [String, Symbol, Module] the Active Record class this database hangs off
      # @return [Briefly::Builder]
      def install(builder, base: "ApplicationRecord")
        model = -> { base.is_a?(Module) ? base : Object.const_get(base) }

        builder.shortcut(:connection, :conn) { model.call.lease_connection }
        builder.shortcut(:transaction, :txn) { |**opts, &blk| model.call.transaction(**opts, &blk) }
        builder.shortcut(:connected_to) { |**opts, &blk| model.call.connected_to(**opts, &blk) }
        # `**opts` first, `role:` last: the pinned role wins over any `role:` in `opts`, so `reading`
        # always reads, while `shard:` and `prevent_writes:` still forward.
        builder.shortcut(:reading) { |**opts, &blk| connected_to(**opts, role: :reading, &blk) }
        builder.shortcut(:writing) { |**opts, &blk| connected_to(**opts, role: :writing, &blk) }
        # `select_all`, the read-optimized path for a raw SELECT: it returns an `ActiveRecord::Result`
        # without clearing the query cache, where `exec_query` is the general read/write form. `query`
        # is a read helper by contract; a write still runs, but out of scope.
        #
        # `with_connection`, not `connection`: the latter is soft-deprecated, and raises outright under
        # `ActiveRecord.permanent_connection_checkout = :disallowed`.
        #
        # A bindless statement must skip `sanitize_sql_array`, which would fall through to its
        # `statement % values` branch and raise on any literal `%` — `... like '%foo%'`.
        #
        # No `**` parameter here, deliberately: taking no keywords is what makes Ruby pack
        # `query(sql, id: 1)` into `binds` as a trailing Hash, which is how named binds reach
        # `sanitize_sql_array`. A `**opts` would swallow them and send the statement unbound.
        builder.shortcut(:query) do |sql, *binds|
          record = model.call
          statement = binds.empty? ? sql : record.sanitize_sql_array([sql, *binds])
          record.with_connection { |connection| connection.select_all(statement) }
        end
        builder
      end
    end
  end
end
