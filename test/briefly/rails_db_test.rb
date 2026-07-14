# frozen_string_literal: true

require "test_helper"
require "support/active_record"

# The DB pack runs against real Active Record on in-memory SQLite (see support/active_record.rb), so
# `with_connection`, `select_all`, `exec_query`, `sanitize_sql_array` and `connected_to` are exercised
# as the framework really behaves, not as a double would echo them.
class RailsDbTest < BrieflyTest
  BASE = "ARTest::ApplicationRecord"

  def setup
    ARTest.reset!
  end

  # `connection`/`conn` is a `with_connection` passthrough: it yields the leased connection and returns
  # the block's value. The connection is live — a query inside the block runs against the database.
  def test_connection_yields_a_live_connection_and_returns_the_block_value
    db = build_db

    assert_kind_of(ActiveRecord::ConnectionAdapters::AbstractAdapter, db.connection { |c| c })
    assert_equal(1, db.conn { |connection| connection.select_value("select 1") })
  end

  # The passthrough forwards every keyword to `with_connection`, so anything Rails accepts there
  # (`prevent_permanent_checkout:` today) reaches it. A module double records the opts it received.
  def test_connection_forwards_keywords_to_with_connection
    received = nil
    model = Module.new do
      define_singleton_method(:with_connection) do |**opts, &blk|
        received = opts
        blk.call(:leased)
      end
    end
    db = Briefly.define { namespace(:db) { use Briefly::Rails::DB, base: model } }.db

    assert_equal :leased, db.connection(prevent_permanent_checkout: true) { |c| c }
    assert_equal({ prevent_permanent_checkout: true }, received)
  end

  # No bare-lease fallback: `with_connection` yields, so a call with no block raises `LocalJumpError`
  # from Rails rather than returning a held, never-released connection.
  def test_connection_without_a_block_raises
    db = build_db

    assert_raises(LocalJumpError) { db.connection }
  end

  # The auto-release contract holds even when the block raises: the connection returns to the pool
  # instead of leaking, which is the whole reason `connection` is a `with_connection` block and not a
  # bare lease. Rails' `with_connection` ensures the release; pinned here so the passthrough can't
  # regress into a leak.
  def test_connection_releases_the_lease_when_the_block_raises
    db = build_db

    assert_raises(RuntimeError) { db.connection { raise "boom" } }

    refute_predicate ARTest::ApplicationRecord.connection_pool, :active_connection?
  end

  # `connection` is soft-deprecated and raises under `permanent_connection_checkout = :disallowed`
  # (set in the harness) once the pool is back to a permanent lease. The pack reaches for
  # `with_connection` instead, so its calls keep working where `.connection` fails.
  def test_the_pack_never_reaches_for_the_deprecated_connection_method
    db = build_db
    ARTest::ApplicationRecord.release_connection

    assert_raises(ActiveRecord::ActiveRecordError) { ARTest::ApplicationRecord.connection }

    db.conn { |c| c }
    db.select("select 1")
    db.query("select 1")
    db.txn { nil }
  end

  def test_transaction_forwards_keywords_and_the_block
    db = build_db

    assert_equal :from_block, db.txn(requires_new: true) { :from_block }
  end

  def test_transaction_commits_on_success_and_rolls_back_on_raise
    db = build_db

    db.txn { insert("carol") }

    assert_equal 4, count

    assert_raises(RuntimeError) do
      db.txn do
        insert("dave")
        raise "boom"
      end
    end
    assert_equal 4, count
  end

  # `select_all` returns an ActiveRecord::Result; rows come back as string-keyed hashes.
  def test_select_returns_a_result_of_rows
    result = build_db.select("select * from items order by id")

    assert_instance_of ActiveRecord::Result, result
    assert_equal([{ "id" => 1, "name" => "ada" }, { "id" => 2, "name" => "bob" },
                  { "id" => 3, "name" => "adalovelace" }], result.to_a)
  end

  # A bindless statement skips `sanitize_sql_array`, whose `statement % values` branch would raise on
  # the literal `%`. Real SQLite proves the row match, not just the absence of a raise.
  def test_select_without_binds_keeps_a_literal_percent
    rows = build_db.select("select * from items where name like '%ada%' order by id").to_a

    assert_equal(%w[ada adalovelace], rows.map { |row| row["name"] })
  end

  def test_select_binds_a_positional_placeholder
    rows = build_db.select("select * from items where id = ?", 1).to_a

    assert_equal [{ "id" => 1, "name" => "ada" }], rows
  end

  # The body takes no keyword parameter, so `id: 2` packs into `binds` as a trailing Hash, which is
  # exactly the named-bind shape `sanitize_sql_array` wants. A `**opts` would swallow it.
  def test_select_binds_named_keywords
    rows = build_db.select("select * from items where id = :id", id: 2).to_a

    assert_equal [{ "id" => 2, "name" => "bob" }], rows
  end

  # `select_all` (not `exec_query`) is a documented invariant — the read-optimized path that keeps the
  # query cache — but every row/shape assertion passes identically under either, so a revert to
  # `exec_query` would ship green. Spy the leased connection (`with_connection` yields that same
  # instance) so the method actually called is pinned, and the invariant has a guard that can fail.
  def test_select_reads_through_select_all_not_exec_query
    reached = spy_adapter_methods

    build_db.select("select * from items")

    assert_equal [:select_all], reached
  end

  # `query`'s sibling invariant: it runs the general path through `exec_query`, not `select_all`. Same
  # spy technique, opposite expectation — the guard fails if the method is swapped.
  def test_query_runs_through_exec_query_not_select_all
    reached = spy_adapter_methods

    build_db.query("select * from items")

    assert_equal [:exec_query], reached
  end

  # `query` runs arbitrary SQL, not just reads: an UPDATE executes and persists.
  def test_query_executes_a_write
    db = build_db

    db.query("update items set name = 'ADA' where id = 1")

    assert_equal "ADA", db.select("select name from items where id = 1").to_a.first["name"]
  end

  # A write keeps the same bind-safety as a read: named binds reach `sanitize_sql_array` and are
  # quoted, not interpolated — an apostrophe round-trips instead of breaking the SQL.
  def test_query_binds_named_keywords_on_a_write
    db = build_db

    db.query("update items set name = :name where id = :id", name: "O'Hara", id: 2)

    assert_equal "O'Hara", db.select("select name from items where id = 2").to_a.first["name"]
  end

  # Routing, not just role forwarding: inside the block the *leased connection* belongs to the role's
  # own pool, so a query physically runs against that database. `current_role` alone would pass even if
  # no connection switch happened; the pool name only changes when the role actually routes.
  def test_reading_and_writing_route_to_the_role_pool
    db = build_db

    assert_equal("primary_replica", db.reading { active_pool })
    assert_equal("primary", db.writing { active_pool })
  end

  # The sugar pins its role: extra keywords forward, but a `role:` in them can't win.
  def test_reading_and_writing_pin_their_role
    db = build_db

    assert_equal(:reading, db.reading(role: :writing) { ARTest::ApplicationRecord.current_role })
    assert_equal(:writing, db.writing(role: :reading) { ARTest::ApplicationRecord.current_role })
  end

  # `connected_to` forwards the whole Rails surface, so any role — not just reading/writing — routes to
  # its own pool, and Rails' own "must provide a role or shard" validation comes through untouched.
  def test_connected_to_forwards_arbitrary_roles
    db = build_db

    assert_equal("primary_replica", db.connected_to(role: :reading) { active_pool })
    assert_equal("analytics", db.connected_to(role: :analytics) { active_pool })
    assert_raises(ArgumentError) { db.connected_to { flunk "connected_to needs a role or shard" } }
  end

  # The other `connected_to` keywords forward through the same `**opts` splat: `shard:` switches the
  # active shard, and `prevent_writes:` toggles the write guard (which the `writing` sugar forwards
  # too). A `**opts` that swallowed these would leave shard `default` and the guard off.
  def test_connected_to_forwards_shard_and_prevent_writes
    db = build_db

    assert_equal(:secondary, db.connected_to(shard: :secondary) { ARTest::ApplicationRecord.current_shard })
    assert(db.writing(prevent_writes: true) { ARTest::ApplicationRecord.current_preventing_writes })
    refute(db.writing { ARTest::ApplicationRecord.current_preventing_writes })
  end

  # `connected_to` is abstract-class-only; on a concrete model Rails raises NotImplementedError — the
  # constraint holds for both sugar shortcuts, which share the `connected_to` code path.
  def test_reading_and_writing_raise_on_a_concrete_model
    db = build_db(base: "ARTest::Item")

    assert_raises(NotImplementedError) { db.reading { flunk "block must not run" } }
    assert_raises(NotImplementedError) { db.writing { flunk "block must not run" } }
  end

  def test_base_accepts_a_module
    model = Module.new { def self.with_connection(**) = yield(:leased) }
    facade = Briefly.define { namespace(:db) { use Briefly::Rails::DB, base: model } }

    assert_equal(:leased, facade.db.conn { |c| c })
  end

  # The dev-reload guarantee: a String base is resolved per call, never captured at install time.
  def test_a_string_base_resolves_the_constant_fresh_per_call
    Object.const_set(:SwappableRecord, Module.new { def self.with_connection(**) = yield(:first) })
    db = Briefly.define { namespace(:db) { use "rails/db", base: "SwappableRecord" } }.db

    assert_equal(:first, db.conn { |c| c })

    Object.send(:remove_const, :SwappableRecord)
    Object.const_set(:SwappableRecord, Module.new { def self.with_connection(**) = yield(:second) })

    assert_equal(:second, db.conn { |c| c })
  ensure
    Object.send(:remove_const, :SwappableRecord) if Object.const_defined?(:SwappableRecord, false)
  end

  # The pack wires no lifecycle hook, so it needs no `Rails.application`.
  def test_the_pack_installs_without_a_booted_application
    refute defined?(::Rails), "this test must run with no ::Rails constant"

    facade = Briefly.define { use Briefly::Rails::DB }

    assert_equal %i[connected_to connection query reading select transaction writing], facade.briefly.shortcuts.sort
  end

  def test_the_pack_memoizes_nothing
    facade = Briefly.define { use Briefly::Rails::DB }

    assert_empty memoized_names(facade)
  end

  def test_only_install_is_public_on_the_pack
    assert_equal %i[install], Briefly::Rails::DB.singleton_methods(false)
  end

  private

  def build_db(base: BASE)
    Briefly.define { namespace(:db) { use "rails/db", base: base } }.db
  end

  # Wraps `select_all` and `exec_query` on the currently-leased connection so each call is recorded.
  # `with_connection` yields this same held instance, so the spy sees whichever method the pack picks.
  # Prepended (not `define_singleton_method`) so two spy tests reusing the pooled connection don't warn
  # about redefining a singleton method.
  def spy_adapter_methods
    connection = ARTest::ApplicationRecord.lease_connection
    reached = []
    recorder = Module.new do
      %i[select_all exec_query].each do |method|
        define_method(method) do |*args, **kwargs, &blk|
          reached << method
          super(*args, **kwargs, &blk)
        end
      end
    end
    connection.singleton_class.prepend(recorder)
    reached
  end

  # The db_config name of the connection currently leased from the pool — "primary" vs "primary_replica"
  # vs "analytics". It changes only when `connected_to` actually routes to that role's pool.
  def active_pool
    ARTest::ApplicationRecord.lease_connection.pool.db_config.name
  end

  def insert(name)
    ARTest::ApplicationRecord.lease_connection.execute("insert into items (name) values ('#{name}')")
  end

  def count
    ARTest::ApplicationRecord.with_connection { |connection| connection.select_value("select count(*) from items") }
  end
end
