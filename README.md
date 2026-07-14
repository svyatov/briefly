# briefly &nbsp; [![Gem Version](https://badge.fury.io/rb/briefly.svg)](https://rubygems.org/gems/briefly) [![CI](https://github.com/svyatov/briefly/actions/workflows/main.yml/badge.svg)](https://github.com/svyatov/briefly/actions/workflows/main.yml) [![codecov](https://codecov.io/gh/svyatov/briefly/branch/main/graph/badge.svg)](https://codecov.io/gh/svyatov/briefly) [![Documentation](https://img.shields.io/badge/docs-rubydoc.info-blue.svg)](https://rubydoc.info/gems/briefly) [![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2-CC342D.svg)](https://www.ruby-lang.org) [![Types: RBS](https://img.shields.io/badge/types-RBS-8A2BE2.svg)](https://github.com/svyatov/briefly/tree/main/sig)

A terse, curated facade over your application's most reached-for objects. Thread-safe, reload-correct,
with a Rails pack included.

Every app grows an `App` module full of `def self.config = Rails.configuration`. `briefly` gives
you that module without writing it, as real methods. There is no `method_missing`, so `respond_to?`,
console tab-completion and test stubbing all work. Each shortcut carries its body's `arity` and
parameter kinds (keyword names are exact, positionals get generated ones), and its `source_location`
is the block you declared, so jump-to-definition lands in your initializer rather than inside the gem.
That fabrication is [candor](https://github.com/svyatov/candor), extracted from this gem and its only
runtime dependency; candor itself has none.

```ruby
# config/initializers/app.rb
App = Briefly.define do
  use "rails"
  shortcut(:redis) { REDIS_POOL }
end

App.c                        # => Rails.configuration
App.x.stripe_key             # => Rails.configuration.x.stripe_key
App.render(:receipt, locals: { order: })
App.redis                    # => REDIS_POOL
App.local?                   # => true in development and test
```

## Installation

```ruby
gem "briefly"
```

Ruby >= 3.2. The one runtime dependency is `candor`. Rails is optional: the gem does not declare
it, and `Briefly::Rails` is autoloaded only when you name it.

In a Rails app, `rails g briefly:install` writes `config/initializers/briefly.rb` — a working `App`
facade plus a commented, concern-grouped map of every shortcut the `rails` pack gives you. Pass a
name (`rails g briefly:install Facade`) to call the constant something else. Re-run it after upgrading
to refresh the map; Rails prompts before overwriting. The generator loads only under `rails generate`,
so it adds no runtime dependency.

## Core concepts

A **facade** is the object `Briefly.define` returns. You assign it to a constant of your choosing;
`briefly` never installs one for you. Multiple independent facades share no state:

```ruby
App   = Briefly.define { use "rails" }
Admin = Briefly.define { shortcut(:audit_log) { AuditLog } }
```

A **shortcut** is a name plus a body. The body is always attached to `shortcut`, one block in one
place, and runs bound to the facade, so it can reach the facade's other shortcuts:

```ruby
Briefly.define do
  shortcut(:config, :c) { Rails.configuration }   # `:c` is an alias
  shortcut(:timeout)    { config.x.timeout }      # bodies see other shortcuts
  shortcut(:ready?)     { !timeout.nil? }         # `?` and `!` names are fine
  shortcut(:fetch)      { |key, &blk| store.get(key, &blk) }  # args and blocks forward
end
```

Aliases are real methods delegating to the same body and the same memo cell. Redeclaring a name
overrides it silently; that is how you override a pack's shortcut.

## `memoize`

Annotate an already-declared shortcut by name, on its own line:

```ruby
Briefly.define do
  shortcut(:catalog) { Catalog.load_from_disk }
  memoize :catalog
end
```

Memoization is permanent for the process; the core has no idea what a "reload" is. It caches
`nil` and `false` correctly, and a body that takes any parameter (positional, keyword, or block)
cannot be memoized (raises at build time). The compiled method takes no arguments either, so
`App.catalog(:x)` is an `ArgumentError`, never a silent cache hit. If a memoized body raises and a
handler supplies a fallback, that shortcut's own cell is not filled: the transient failure is
retried on next call.

That guarantee is per-cell, and does not compose. A memoized shortcut whose body *reads* a
rescue-backed shortcut succeeds, so its own value (containing the fallback) is cached for the
process lifetime, even after the inner shortcut recovers:

```ruby
shortcut(:flaky) { external_call }        # rescue_from(..., :flaky) { "unknown" }
memoize :flaky
shortcut(:summary) { "build #{flaky}" }   # caches "build unknown" forever
memoize :summary                          # <- don't memoize over a rescue-backed shortcut
```

Clearing is a neutral primitive. Management lives behind one accessor, `App.briefly`, so names like
`configure`, `shortcuts`, `shortcut?` and `clear_memos!` stay yours to use as shortcuts:

```ruby
App.briefly.clear_memos!   # => App     (thread-safe)
```

Reclaim one of those names and `App.configure` calls *your* shortcut — the old management call now
lives only at `App.briefly.configure`. Worth knowing when porting pre-0.2.0 code: a leftover
`App.configure { ... }` won't raise if a `configure` shortcut exists, it just runs the shortcut and,
like any non-yielding method, drops the block.

*When* to clear is a pack's business. See [Reloading](#reloading-and-thread-safety).

## `rescue_from`

Error class first, shortcut names optional and trailing. The handler's return value becomes the
shortcut's return value:

```ruby
Briefly.define do
  use "rails"
  shortcut(:redis) { REDIS_POOL }
  rescue_from(Redis::BaseError, :redis) { |e| Sentry.capture_exception(e); nil }
  rescue_from(StandardError) { |e, name| Rails.logger.warn("#{name}: #{e.message}"); raise }
end
```

Unlike a shortcut body, a handler is not bound to the facade. It is called as
`handler.call(error, name)`, so `self` stays whatever it was where you wrote the block. Reach for
constants (`Rails.logger`, `Sentry`) rather than bare shortcut names inside a handler.

> **A facade-wide `rescue_from(StandardError)` catches your own bugs, not just your app's.**
> `briefly` cannot tell an error raised *by* a shortcut body from one raised *about* the call; a
> typo and a dead Redis both arrive as a `StandardError`:
>
> ```ruby
> shortcut(:host) { Rails.aplication.config.host }   # typo -> NoMethodError
> rescue_from(StandardError) { nil }
>
> App.host     # => nil. No exception, no log, no clue.
> ```
>
> Three ways out, in order of preference: scope handlers to the shortcuts that can actually fail;
> match the narrowest error class you mean; and if you do want a facade-wide handler, make it log
> and `raise`. A bare `raise` inside a handler re-raises the original, backtrace intact.
>
> A bad *call* from outside the facade is not affected. Every shortcut carries its body's arity, so
> `App.env(1)` raises `ArgumentError` at the call site, before any handler is consulted. One shortcut
> body calling another with a bad argument list is a different matter: that raises *inside* the
> calling body, where the calling shortcut's own handler sees it like any other error.

> **⚠️ `{}` needs parentheses.** `rescue_from StandardError { ... }` binds the block to
> `StandardError`, not to `rescue_from`, and raises `NoMethodError`. Use either form:
>
> ```ruby
> rescue_from StandardError, :redis do |e| ... end   # do/end, no parens
> rescue_from(StandardError, :redis) { |e| ... }     # braces REQUIRE parens
> ```

Handlers are plain procs, so `{ |e| }` and `{ |e, name| }` both work. Re-raising propagates. If no
handler matches, the original error propagates unchanged, never silently swallowed. Only
`StandardError` and its descendants participate.

`Briefly.rescue_from(error_class, &handler)` registers a global default across every facade. It
takes no shortcut names.

### Resolution order

For a raised error, the first `is_a?` match wins, searching in this order:

| # | Level | Within the level |
|---|-------|------------------|
| 1 | Facade handlers scoped to this shortcut | last registered first |
| 2 | Facade handlers with no names | last registered first |
| 3 | Global handlers (`Briefly.rescue_from`) | last registered first |

No match → the error propagates.

## `namespace`

`namespace` groups shortcuts behind a name, so the root keyspace stays yours:

```ruby
App = Briefly.define do
  shortcut(:redis) { REDIS_POOL }

  namespace :db do
    shortcut(:pool) { ActiveRecord::Base.connection_pool }
    memoize :pool
  end
end

App.redis     # => REDIS_POOL
App.db        # => #<Briefly::Facade shortcuts=[:pool]>
App.db.pool   # => the pool
```

A namespace is a child `Briefly::Facade`, reached by a real method like any other shortcut, so
`App.db` is a value you can pass around, and `App.db.pool` is not a `method_missing` trick. It takes
the whole DSL: `shortcut`, `memoize`, `rescue_from`, `use`, and further namespaces.

`clear_memos!` cascades, so one `Briefly::Rails::Reload` on the root clears the whole tree. The child
is created once and reused, so its memos survive a later `configure`.

`configure` is atomic across the whole tree: a pass that raises anywhere leaves the root and every
namespace under it exactly as they were. Declaring `shortcut(:db)` over a `namespace(:db)` overrides
it and drops the child.

Two limits, both deliberate:

- A child body cannot call a root shortcut by bare name. Namespaces are self-contained.
- A root `rescue_from` does not scope into a child. Register handlers inside the namespace, or
  globally with `Briefly.rescue_from`.

## Packs

A pack is any object responding to `#install(builder, **opts)`. Options are optional: Ruby drops an
empty `**` splat, so a pack taking none needs no keyword parameter.

```ruby
module RedisPack
  module_function

  def install(builder)
    builder.shortcut(:redis) { ConnectionPool.new { Redis.new } }
    builder.memoize(:redis)
    builder.rescue_from(Redis::CannotConnectError, :redis) { nil }
  end
end

Api = Briefly.define { use RedisPack }
```

Packs may `use` other packs, and may reach `builder.facade` to wire lifecycle hooks, which is
exactly what `Briefly::Rails::Reload` does. The core stays framework-agnostic; packs do not have to.

### Options

Keywords passed to `use` reach the pack's `install`. Ruby drops an empty `**` splat, so a pack that
takes no options needs no keyword parameter:

```ruby
module RedisPack
  module_function

  def install(builder, url: ENV.fetch("REDIS_URL"))
    builder.shortcut(:redis) { ConnectionPool.new { Redis.new(url: url) } }
  end
end

Api = Briefly.define { use RedisPack, url: "redis://cache:6379" }
```

### Short names

`Briefly.register` maps a name to a pack, so `use` can take a string or symbol. There is no
inflection and no path guessing; the registry is the only source of truth:

```ruby
Briefly.register("myapp/redis", RedisPack)          # a pack object
Briefly.register("myapp/redis", "MyApp::RedisPack") # or a constant path, resolved on first use

Api = Briefly.define { use "myapp/redis", url: "redis://cache:6379" }
```

An unregistered name raises `Briefly::UnknownPackError`. The packs this gem ships are registered as
`"rails"`, `"rails/config"`, `"rails/env"`, `"rails/view"`, `"rails/db"`, `"rails/instrument"` and
`"rails/reload"`.

### `Briefly::Rails`

| shortcut | aliases | value |
|---|---|---|
| `config` | `c` | `Rails.configuration` |
| `config_x` | `x` | `Rails.configuration.x` |
| `env` | | `Rails.env` |
| `production?` `development?` `test?` `local?` | `prod?` `dev?` | `Rails.env.*` |
| `root` | | `Rails.root` |
| `cache` | | `Rails.cache` |
| `logger` | `log` | `Rails.logger` |
| `credentials` | `cred` | `Rails.application.credentials` |
| `error` | | `Rails.error` |
| `config_for` | | `Rails.application.config_for(name, **opts)` |
| `helpers` | `h` | `ApplicationController.helpers` |
| `routes` | `r` | `Rails.application.routes.url_helpers` |
| `renderer` | | `ApplicationController.renderer` |
| `render` | | forwards to `renderer.render` |
| `instrument` | | `ActiveSupport::Notifications.instrument(name, payload) { }` |

Plus `db`, a namespace holding `Briefly::Rails::DB`.

`prod?` and `dev?` alias `production?` and `development?`. `error` is the framework's handled-error
reporter, so `App.error.report(e)` and `App.error.handle { }` reach it off one live lookup.
`config_for` reads a per-environment YAML config on every call and forwards any extra keyword (such
as `env:`) to `Rails.application.config_for`: it takes an argument, so it never memoizes; compose one
that does by declaring a shortcut, then memoizing it: `shortcut(:payments) { config_for(:payments) }`
then `memoize(:payments)`.

Requires Rails >= 7.2. There is no `secrets` shortcut: `Rails.application.secrets` was removed in
7.2. Use `credentials`.

Nothing in the pack is memoized. `helpers`, `routes` and `renderer` are live lookups: Rails
already caches them on objects it refreshes on reload, so caching them again would only go stale.
It still composes `Briefly::Rails::Reload`, because *your* memoized shortcuts need clearing.

Need a custom renderer? Override it; last declaration wins:

```ruby
App = Briefly.define do
  use "rails"
  shortcut(:renderer) { ApplicationController.renderer.new(http_host: x.domain, https: !development?) }
end
```

`Briefly::Rails` is an umbrella over five packs, each usable on its own:

| pack | short name | shortcuts |
|---|---|---|
| `Briefly::Rails::Config` | `"rails/config"` | `config`, `config_x`, `root`, `cache`, `logger`, `credentials`, `error`, `config_for` |
| `Briefly::Rails::Env` | `"rails/env"` | `env` and its predicates |
| `Briefly::Rails::View` | `"rails/view"` | `helpers`, `routes`, `renderer`, `render` |
| `Briefly::Rails::DB` | `"rails/db"` | `connection`, `transaction`, `select`, `query`, `connected_to`, `reading`, `writing` |
| `Briefly::Rails::Instrument` | `"rails/instrument"` | `instrument` |

```ruby
Worker = Briefly.define do
  use "rails/env"
  use "rails/reload"
  namespace(:db) { use "rails/db" }
end
```

### `Briefly::Rails::DB`

| shortcut | aliases | value |
|---|---|---|
| `connection` | `conn` | forwards keywords and the block to `base.with_connection` — yields the connection, auto-releases |
| `transaction` | `txn` | forwards keywords and the block to `base.transaction` |
| `select` | | `base.with_connection { \|c\| c.select_all(sql) }` — a read (SELECT) on the cache-aware path |
| `query` | | `base.with_connection { \|c\| c.exec_query(sql) }` — arbitrary SQL, writes and DDL included |
| `connected_to` | | forwards every argument to `base.connected_to` (`role:`, `shard:`, `prevent_writes:`) |
| `reading` | | runs the block under the `:reading` role |
| `writing` | | runs the block under the `:writing` role |

```ruby
App = Briefly.define do
  use "rails"
  namespace(:db2) { use "rails/db", base: "SecondaryApplicationRecord" }
end

App.db.txn { App.db.select("select * from users where id = ?", 1) }
App.db.conn { |c| c.select_value("select count(*) from users") }
```

`select` and `query` are the two raw-SQL helpers, differing only in which adapter path they take.
`select(sql, *binds)` runs a read through `select_all` — the path Rails recommends for a raw SELECT,
returning an `ActiveRecord::Result` without clearing the query cache. `query(sql, *binds)` runs
arbitrary SQL through `exec_query`: reads, writes, and DDL all execute. The name tells you which
you're reaching for; neither polices the SQL it's handed, so `select` will happily run a write you
give it — the split is name and cache-path, not a runtime guard.

Both sanitize through `base.sanitize_sql_array` when binds are given, and pass the statement through
untouched when they are not. Positional and named binds both work:

```ruby
App.db.select("select * from users where name like '%ada%'")         # no binds, passed through
App.db.select("select * from users where id = ?", 123)               # positional
App.db.query("update users set active = true where id = :id", id: 1) # named, a write via `query`
```

Binds are bound, never interpolated, so a value like `"x' OR '1'='1"` matches nothing. A bindless
statement is not sanitized on purpose: `sanitize_sql_array` would fall through to its
`statement % values` branch and raise on the literal `%` above. That makes binds a safety contract,
not a convenience: always pass untrusted values as binds. The bindless path is unsanitized, and since
`query` now runs writes and DDL, an interpolated statement is a destructive-write injection risk, not
merely a read one.

`connection`/`conn` mirrors `transaction`: it forwards to `with_connection`, yields the leased
connection, and auto-releases at block exit, so nothing leaks outside a request. It requires a block —
there is no bare-lease accessor. Anyone who genuinely needs a held raw lease calls `lease_connection`
on their model directly.

`reading` and `writing` *route* a block — everything inside runs under that connection role, so you
send specific reads to a replica or pin a write to the primary:

```ruby
App.db.reading { App.db.select("select * from reports") }  # runs on the replica
App.db.writing { Audit.create!(event: "export") }          # pinned to the primary
```

They're sugar over `connected_to`, which is also a shortcut in its own right and forwards the whole
Rails surface — any role (not just reading/writing), plus `shard:` and `prevent_writes:`:

```ruby
App.db.connected_to(role: :analytics) { Report.all.to_a }   # a custom role
App.db.connected_to(shard: :one) { Order.find(id) }         # a shard
App.db.reading(shard: :two) { ... }                         # sugar forwards the rest too
```

The `reading`/`writing` sugar pins its role: a `role:` you pass through it can't win, so `reading`
always reads. All of this needs a multi-database app: `base` must be `ActiveRecord::Base` or the
abstract class that declared `connects_to(database: { ... })`. On a concrete model `connected_to`
raises `NotImplementedError`, and in a single-database app with no matching connection
`App.db.reading { ... }` raises `ActiveRecord::ConnectionNotDefined` — these are a multi-DB tool, not a
role flag.

**Pass `base:` as a String, not the class.** A pack is `use`d from an initializer, where naming an
autoloadable constant is what Rails warns about, and the captured class would go stale on the first
code reload and stay stale, since `Reload` clears memos, not closures. A `Module` is accepted for
applications outside the autoloader, with that caveat.

The pack memoizes nothing and wires no lifecycle hook, so it works without a booted application.

### `Briefly::Rails::Reload`

`Briefly::Rails` composes it. Use it alone for a facade with no framework shortcuts that still
memoizes objects holding on to reloadable application classes:

```ruby
Admin = Briefly.define do
  use "rails/reload"
  shortcut(:policy) { Admin::Policy.new }
  memoize :policy
end
```

It registers `Rails.application.reloader.to_prepare { facade.briefly.clear_memos! }`, so memos are dropped
at boot and on every code reload in development. In production nothing reloads, so they persist for
the process lifetime. It raises `Briefly::Error` outside a booted app, so call it from an initializer.

The callback holds its facade for the process lifetime and cannot be deregistered. Install it on
long-lived facades assigned to constants, not on facades built per request.

## Reloading and thread-safety

Memo reads are lock-free against a frozen snapshot; writes swap in a new frozen hash under a
reentrant lock, so a memoized body may safely call another memoized shortcut. Under Puma, a
memoized body runs exactly once no matter how many threads race for it.

`clear_memos!` guarantees the *next* read recomputes. It does not undo in-place mutation of an
already-handed-out object, and it does not survive a process restart. Two facades whose memoized
bodies call into each other can deadlock, like any pair of mutually-locking objects; don't do that.

## Testing

Shortcuts are real methods, so nothing special is needed:

```ruby
allow(App).to receive(:redis).and_return(fake_redis)   # rspec-mocks verifies it
App.stub(:redis, fake_redis) { ... }                   # minitest
```

Call `App.briefly.clear_memos!` between examples if a memoized value would leak. `Briefly.errors.clear`
resets globally registered handlers.

## Types

`briefly` ships RBS signatures in [`sig/`](sig). Shortcuts are compiled at runtime, so RBS cannot
see them. `Briefly.define`, `Facade`'s lifecycle API and the `Builder` DSL are fully typed, but
`App.config` is invisible to Steep. Declare the ones you rely on in your own `sig/`:

```rbs
App: Briefly::Facade

def App.config: () -> untyped
def App.redis: () -> untyped
```

We do not fake this with an RBS-only `method_missing`; the gem has none.

## Migrating a hand-rolled `App`

```ruby
# before
module App
  def self.config      = Rails.configuration
  def self.c           = config
  def self.x           = config.x
  def self.env         = Rails.env
  def self.helpers     = @helpers ||= ApplicationController.helpers    # stale after reload
  def self.routes      = @routes  ||= Rails.application.routes.url_helpers
  def self.render(...) = ApplicationController.renderer.render(...)
  def self.secrets     = Rails.application.secrets                     # gone in Rails 7.2
  def self.redis       = @redis ||= REDIS_POOL
end

# after
App = Briefly.define do
  use "rails"
  shortcut(:redis) { REDIS_POOL }
  memoize :redis
end
```

`secrets` becomes `credentials`. `helpers`/`routes` stop going stale because they are no longer
memoized, and `redis` (which you *do* want memoized) is cleared on every dev reload by the Reload
pack that `Briefly::Rails` composes.

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE.txt).
