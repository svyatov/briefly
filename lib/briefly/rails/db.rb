# frozen_string_literal: true

module Briefly
  module Rails
    # Shortcut pack for a single database, reached through one Active Record class.
    #
    #   App = Briefly.new do
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
          record.with_connection { |connection| connection.exec_query(statement) }
        end
        builder
      end
    end
  end
end
