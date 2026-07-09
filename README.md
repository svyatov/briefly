# briefly

[![Gem Version](https://badge.fury.io/rb/briefly.svg)](https://rubygems.org/gems/briefly)
[![CI](https://github.com/svyatov/briefly/actions/workflows/main.yml/badge.svg)](https://github.com/svyatov/briefly/actions/workflows/main.yml)
[![codecov](https://codecov.io/gh/svyatov/briefly/branch/main/graph/badge.svg)](https://codecov.io/gh/svyatov/briefly)
[![Documentation](https://img.shields.io/badge/docs-rubydoc.info-blue.svg)](https://rubydoc.info/gems/briefly)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2-CC342D.svg)](https://www.ruby-lang.org)
[![Types: RBS](https://img.shields.io/badge/types-RBS-8A2BE2.svg)](https://github.com/svyatov/briefly/tree/main/sig)

A terse, curated facade over your application's most reached-for objects — **dependency-free**,
**thread-safe**, **reload-correct**, with a batteries-included Rails pack.

Every app grows an `App` module full of `def self.config = Rails.configuration`. `briefly` gives
you that module without writing it, as **real methods** — no `method_missing`, so `respond_to?`,
console tab-completion and test stubbing all just work.

```ruby
# config/initializers/app.rb
App = Briefly.new do
  use Briefly::Rails
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

Ruby >= 3.2. Rails is an **optional** dependency: the gem declares none, and `Briefly::Rails` is
autoloaded only when you name it.

## Core concepts

A **facade** is the object `Briefly.new` returns. You assign it to a constant of your choosing;
`briefly` never installs one for you. Multiple independent facades share no state:

```ruby
App   = Briefly.new { use Briefly::Rails }
Admin = Briefly.new { shortcut(:audit_log) { AuditLog } }
```

A **shortcut** is a name plus a body. The body is always attached to `shortcut` — one block, one
place — and runs bound to the facade, so it can reach the facade's other shortcuts:

```ruby
Briefly.new do
  shortcut(:config, :c) { Rails.configuration }   # `:c` is an alias
  shortcut(:timeout)    { config.x.timeout }      # bodies see other shortcuts
  shortcut(:ready?)     { !timeout.nil? }         # `?` and `!` names are fine
  shortcut(:fetch)      { |key, &blk| store.get(key, &blk) }  # args and blocks forward
end
```

Aliases are real methods delegating to the same body and the same memo cell. Redeclaring a name
overrides it silently — that is how you override a pack's shortcut.

## `memoize`

Annotate an already-declared shortcut by name, on its own line:

```ruby
Briefly.new do
  shortcut(:catalog) { Catalog.load_from_disk }
  memoize :catalog
end
```

Memoization is **permanent for the process** — the core has no idea what a "reload" is. It caches
`nil` and `false` correctly, and a body that takes any parameter — positional, keyword, or block —
cannot be memoized (raises at build time). The compiled method takes no arguments either, so
`App.catalog(:x)` is an `ArgumentError`, never a silent cache hit. If a memoized body raises and a
handler supplies a fallback, **that shortcut's own cell is not filled**: the transient failure is
retried on next call.

That guarantee is per-cell, and does not compose. A memoized shortcut whose body *reads* a
rescue-backed shortcut succeeds, so its own value — containing the fallback — is cached for the
process lifetime, even after the inner shortcut recovers:

```ruby
shortcut(:flaky) { external_call }        # rescue_from(..., :flaky) { "unknown" }
memoize :flaky
shortcut(:summary) { "build #{flaky}" }   # caches "build unknown" forever
memoize :summary                          # <- don't memoize over a rescue-backed shortcut
```

Clearing is a neutral primitive:

```ruby
App.clear_memos!   # => App     (thread-safe; `reset!` is an alias)
```

*When* to clear is a pack's business. See [Reloading](#reloading-and-thread-safety).

## `rescue_from`

Error class first, shortcut names optional and trailing. The handler's **return value becomes the
shortcut's return value**:

```ruby
Briefly.new do
  use Briefly::Rails
  shortcut(:redis) { REDIS_POOL }
  rescue_from(Redis::BaseError, :redis) { |e| Sentry.capture_exception(e); nil }
  rescue_from(StandardError) { |e, name| Rails.logger.warn("#{name}: #{e.message}"); raise }
end
```

Unlike a shortcut body, a handler is **not** bound to the facade — it is called as
`handler.call(error, name)`, so `self` stays whatever it was where you wrote the block. Reach for
constants (`Rails.logger`, `Sentry`) rather than bare shortcut names inside a handler.

> **A facade-wide `rescue_from(StandardError)` catches your own bugs, not just your app's.**
> `briefly` cannot tell an error raised *by* a shortcut body from one raised *about* the call — a
> typo and a dead Redis both arrive as a `StandardError`:
>
> ```ruby
> shortcut(:host) { Rails.aplication.config.host }   # typo -> NoMethodError
> rescue_from(StandardError) { nil }
>
> App.host     # => nil. No exception, no log, no clue.
> App.env(1)   # => nil. Wrong arity, silently accepted.
> ```
>
> Three ways out, in order of preference: scope handlers to the shortcuts that can actually fail;
> match the narrowest error class you mean; and if you do want a facade-wide handler, make it log
> and `raise` — a bare `raise` inside a handler re-raises the original, backtrace intact.
>
> The one exception is memoized shortcuts. They compile to zero-argument methods, so `App.catalog(1)`
> raises `ArgumentError` from the method itself, before any handler is consulted.

> **⚠️ `{}` needs parentheses.** `rescue_from StandardError { ... }` binds the block to
> `StandardError`, not to `rescue_from`, and raises `NoMethodError`. Use **either** form:
>
> ```ruby
> rescue_from StandardError, :redis do |e| ... end   # do/end, no parens
> rescue_from(StandardError, :redis) { |e| ... }     # braces REQUIRE parens
> ```

Handlers are plain procs, so `{ |e| }` and `{ |e, name| }` both work. Re-raising propagates. If no
handler matches, the original error propagates unchanged — never silently swallowed. Only
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

## Packs

A pack is **any object responding to `#install(builder)`**. That's the whole protocol.

```ruby
module RedisPack
  module_function

  def install(builder)
    builder.shortcut(:redis) { ConnectionPool.new { Redis.new } }
    builder.memoize(:redis)
    builder.rescue_from(Redis::CannotConnectError, :redis) { nil }
  end
end

Api = Briefly.new { use RedisPack }
```

Packs may `use` other packs, and may reach `builder.facade` to wire lifecycle hooks — that is
exactly what `Briefly::Rails::Reload` does. The core stays framework-agnostic; packs do not have to.

### `Briefly::Rails`

| shortcut | aliases | value |
|---|---|---|
| `config` | `c` | `Rails.configuration` |
| `config_x` | `x` | `Rails.configuration.x` |
| `env` | | `Rails.env` |
| `production?` `development?` `test?` `local?` | | `Rails.env.*` |
| `root` | | `Rails.root` |
| `cache` | | `Rails.cache` |
| `logger` | `log` | `Rails.logger` |
| `credentials` | `cred` | `Rails.application.credentials` |
| `helpers` | `h` | `ApplicationController.helpers` |
| `routes` | `r` | `Rails.application.routes.url_helpers` |
| `renderer` | | `ApplicationController.renderer` |
| `render` | | forwards to `renderer.render` |

Requires Rails >= 7.2. There is no `secrets` shortcut: `Rails.application.secrets` was removed in
7.2. Use `credentials`.

**Nothing in the pack is memoized.** `helpers`, `routes` and `renderer` are live lookups: Rails
already caches them on objects it refreshes on reload, so caching them again would only go stale.

Need a custom renderer? Override it — last declaration wins:

```ruby
App = Briefly.new do
  use Briefly::Rails
  shortcut(:renderer) { ApplicationController.renderer.new(http_host: x.domain, https: !development?) }
end
```

### `Briefly::Rails::Reload`

`Briefly::Rails` composes it. Use it alone for a facade with no framework shortcuts that still
memoizes objects holding on to reloadable application classes:

```ruby
Admin = Briefly.new do
  use Briefly::Rails::Reload
  shortcut(:policy) { Admin::Policy.new }
  memoize :policy
end
```

It registers `Rails.application.reloader.to_prepare { facade.clear_memos! }`, so memos are dropped
at boot and on every code reload in development. In production nothing reloads, so they persist for
the process lifetime. It raises `Briefly::Error` outside a booted app — call it from an initializer.

The callback holds its facade for the process lifetime and cannot be deregistered. Install it on
long-lived facades assigned to constants, not on facades built per request.

## Reloading and thread-safety

Memo reads are lock-free against a frozen snapshot; writes swap in a new frozen hash under a
reentrant lock, so a memoized body may safely call another memoized shortcut. Under Puma, a
memoized body runs exactly once no matter how many threads race for it.

`clear_memos!` guarantees the *next* read recomputes. It does **not** undo in-place mutation of an
already-handed-out object, and it does not survive a process restart. Two facades whose memoized
bodies call into each other can deadlock, like any pair of mutually-locking objects; don't do that.

## Testing

Shortcuts are real methods, so nothing special is needed:

```ruby
allow(App).to receive(:redis).and_return(fake_redis)   # rspec-mocks verifies it
App.stub(:redis, fake_redis) { ... }                   # minitest
```

Call `App.reset!` between examples if a memoized value would leak. `Briefly.errors.clear` resets
globally registered handlers.

## Types

`briefly` ships RBS signatures in [`sig/`](sig). Shortcuts are compiled at runtime, so **RBS cannot
see them** — `Briefly.new`, `Facade`'s lifecycle API and the `Builder` DSL are fully typed, but
`App.config` is invisible to Steep. Declare the ones you rely on in your own `sig/`:

```rbs
App: Briefly::Facade

def App.config: () -> untyped
def App.redis: () -> untyped
```

We deliberately do not fake this with an RBS-only `method_missing`; the gem genuinely has none.

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
App = Briefly.new do
  use Briefly::Rails
  shortcut(:redis) { REDIS_POOL }
  memoize :redis
end
```

`secrets` becomes `credentials`. `helpers`/`routes` stop going stale because they are no longer
memoized, and `redis` — which you *do* want memoized — is cleared on every dev reload by the Reload
pack that `Briefly::Rails` composes.

## Contributing

Bug reports and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE.txt).
