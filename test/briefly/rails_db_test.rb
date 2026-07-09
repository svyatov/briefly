# frozen_string_literal: true

require "test_helper"
require "support/rails_double"

class RailsDbTest < BrieflyTest
  def test_connection_leases_from_the_pool
    with_db do |model, db|
      assert_same model.leased, db.connection
      assert_same model.leased, db.conn
    end
  end

  # `connection` is soft-deprecated and raises under `permanent_connection_checkout = :disallowed`.
  # The double raises on it, so a regression fails here rather than only in production.
  def test_the_pack_never_reaches_for_the_deprecated_connection_method
    with_db do |model, db|
      assert_raises(NoMethodError) { model.connection }

      db.conn
      db.query("select 1")
      db.query("select * from users where id = ?", 1)
    end
  end

  def test_transaction_forwards_keywords_and_the_block
    with_db do |model, db|
      assert_equal :from_block, db.txn(requires_new: true) { :from_block }
      assert_equal [{ requires_new: true }], model.transactions
    end
  end

  # Sanitizing a bindless statement would reach `sanitize_sql_array`'s `statement % values` branch,
  # which raises on the literal `%` below.
  def test_query_without_binds_is_not_sanitized
    with_db do |model, db|
      assert_equal :result, db.query("select * from users where name like '%ada%'")
      assert_equal ["select * from users where name like '%ada%'"], model.leased.queries
      assert_empty model.sanitized
    end
  end

  # `query(sql, *binds)` rather than swallowing the extras: dropping a bind would run the raw string.
  def test_query_with_binds_is_sanitized
    with_db do |model, db|
      db.query("select * from users where id = ?", 1)

      assert_equal [["select * from users where id = ?", 1]], model.sanitized
      assert_equal ['sanitized(["select * from users where id = ?", 1])'], model.leased.queries
    end
  end

  # The body takes no keywords, so Ruby packs them into `binds` as a trailing Hash, which is exactly
  # what `sanitize_sql_array` wants for named binds. A `**opts` parameter on the body would swallow
  # them, and the statement would reach the database unbound.
  def test_query_accepts_named_binds_as_keywords
    with_db do |model, db|
      db.query("select * from users where id = :id", id: 1)

      assert_equal [["select * from users where id = :id", { id: 1 }]], model.sanitized
    end
  end

  def test_base_selects_the_active_record_class
    with_db do |primary, _db|
      secondary = RailsDouble::Model.new
      Object.const_set(:SecondaryRecord, secondary)
      facade = Briefly.new { namespace(:db2) { use "rails/db", base: "SecondaryRecord" } }

      facade.db2.txn { :ok }

      assert_equal [{}], secondary.transactions
      assert_empty primary.transactions
    ensure
      Object.send(:remove_const, :SecondaryRecord)
    end
  end

  def test_base_accepts_a_module
    model = Module.new { def self.lease_connection = :leased }
    facade = Briefly.new { namespace(:db) { use Briefly::Rails::DB, base: model } }

    assert_equal :leased, facade.db.conn
  end

  # The dev-reload guarantee: a String base is resolved per call, never captured at install time.
  def test_a_string_base_follows_a_reloaded_constant
    with_db do |_model, db|
      db.conn
      replacement = RailsDouble::Model.new
      Object.send(:remove_const, :ApplicationRecord)
      Object.const_set(:ApplicationRecord, replacement)

      assert_same replacement.leased, db.conn
    end
  end

  # The pack wires no lifecycle hook, so it needs no `Rails.application`.
  def test_the_pack_installs_without_a_booted_application
    refute defined?(::Rails), "this test must run with no ::Rails constant"

    facade = Briefly.new { use Briefly::Rails::DB }

    assert_equal %i[connection query transaction], facade.shortcuts
  end

  def test_the_pack_memoizes_nothing
    facade = Briefly.new { use Briefly::Rails::DB }

    assert_empty memoized_names(facade)
  end

  def test_only_install_is_public_on_the_pack
    assert_equal %i[install], Briefly::Rails::DB.singleton_methods(false)
  end

  def test_the_umbrella_mounts_the_pack_under_db
    RailsDouble.with(root: Dir.pwd) do |_rails, _controller, model|
      facade = Briefly.new { use Briefly::Rails }

      result = facade.db.txn { :from_block }

      assert_equal :from_block, result
      assert_equal [{}], model.transactions
      refute facade.shortcut?(:txn), "the umbrella must add no root-level DB names"
    end
  end

  private

  # `use Briefly::Rails::DB` alone: no ::Rails, so the reload pack is provably not wired in.
  def with_db
    model = RailsDouble::Model.new
    Object.const_set(:ApplicationRecord, model)
    yield model, Briefly.new { namespace(:db) { use "rails/db" } }.db
  ensure
    Object.send(:remove_const, :ApplicationRecord) if Object.const_defined?(:ApplicationRecord, false)
  end
end
