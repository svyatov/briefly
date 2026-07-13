# frozen_string_literal: true

require "active_record"

# A real Active Record environment on in-memory SQLite, so the DB pack's calls — `lease_connection`,
# `with_connection`, `select_all`, `sanitize_sql_array`, `connected_to` — run against the framework
# instead of a double that echoes any method. The forwarding packs keep the lightweight `::Rails`
# double; only the DB pack earns a real backend, and this is where a wrong AR call actually fails.
#
# The base lives under `ARTest` so it never collides with the top-level `ApplicationRecord` that
# `RailsDouble.with` sets and removes. `permanent_connection_checkout = :disallowed` mirrors the
# production setting under which `.connection` raises, so the pack's `lease_connection` discipline is
# verified rather than assumed.
module ARTest
  # A distinct in-memory database per role, each its own connection pool, so `connected_to(role:)`
  # resolves a different pool without real replicas — that pool difference is what the routing tests
  # assert (`lease_connection.pool.db_config.name`), proving a query would physically hit the role's
  # database, not merely that `current_role` echoes the argument. Schema and data live on the writing
  # (primary) connection, where `query` and `transaction` run. `analytics` is a non-reading/writing
  # role proving `connected_to` reaches arbitrary roles; the `secondary` shard (declared below) proves
  # `shard:` forwards through the same splat as `role:`.
  ENV_NAME = ActiveRecord::ConnectionHandling::DEFAULT_ENV.call
  CONFIG = {
    ENV_NAME => {
      "primary" => { "adapter" => "sqlite3", "database" => ":memory:" },
      "primary_replica" => { "adapter" => "sqlite3", "database" => ":memory:", "replica" => true },
      "analytics" => { "adapter" => "sqlite3", "database" => ":memory:", "replica" => true }
    }
  }.freeze

  ActiveRecord::Base.configurations = CONFIG
  ActiveRecord.permanent_connection_checkout = :disallowed

  # Abstract connection class, the shape `connected_to` requires: `ActiveRecord::Base` or an abstract
  # class that declared `connects_to`. A concrete model raises `NotImplementedError` from it.
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
    connects_to shards: {
      default: { writing: :primary, reading: :primary_replica, analytics: :analytics },
      secondary: { writing: :primary, reading: :primary_replica }
    }
  end

  # A concrete model, used only to prove `connected_to` raises off `ApplicationRecord`.
  class Item < ApplicationRecord
  end

  # Rebuilds the schema and seeds a deterministic set on the writing connection. Called from `setup`,
  # so each test starts from the same three rows: `like '%ada%'` matches ids 1 and 3.
  def self.reset!
    ApplicationRecord.release_connection
    ApplicationRecord.with_connection do |connection|
      connection.execute("drop table if exists items")
      connection.execute("create table items (id integer primary key, name varchar)")
      connection.execute("insert into items (id, name) values (1, 'ada'), (2, 'bob'), (3, 'adalovelace')")
    end
  end
end
