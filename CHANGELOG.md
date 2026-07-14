# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) and to [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## Unreleased

## v0.2.0 (2026-07-14)

### Added
- `rails g briefly:install` — a Rails generator that writes `config/initializers/briefly.rb`: a
  working `App` facade plus a commented, concern-grouped map of every shortcut `use "rails"` installs.
  Pass a name (`rails g briefly:install Facade`) to rename the constant; re-run it after upgrading to
  refresh the map, as Rails prompts before overwriting. It loads only under `rails generate`, so no
  Rails runtime dependency is added.
- `Briefly::Rails::Config` gains `error` (`Rails.error`, the framework's handled-error reporter) and
  `config_for` (per-environment YAML via `Rails.application.config_for`). Both are live lookups;
  `config_for` takes an argument, so it never memoizes — compose one that does by chaining `.memoize`
  onto a shortcut: `shortcut(:x) { config_for(:x) }.memoize`.
- `Briefly::Rails::DB` gains `connected_to`, `reading` and `writing` for multi-database routing.
  `connected_to` forwards the full Rails surface (`role:`, `shard:`, `prevent_writes:`, custom roles);
  `reading`/`writing` are sugar that pin their role and forward the rest. `base` must be
  `ActiveRecord::Base` or an abstract connection class; a concrete model raises `NotImplementedError`.
- `Briefly::Rails::DB` gains `select` — a raw-SQL read through `select_all`, returning an
  `ActiveRecord::Result` on the query-cache-preserving path, with the same positional and named
  bind-safety as `query`. `query` keeps running arbitrary SQL (writes and DDL included) via `exec_query`.
- `Briefly::Rails::Env` gains `dev?` and `prod?`, aliases of `development?` and `production?`.
- `Briefly::Rails::Instrument` — a new `"rails/instrument"` pack with one `instrument` shortcut over
  `ActiveSupport::Notifications.instrument(name, payload) { }`. Usable on its own; `use "rails"`
  includes it, so `App.instrument` comes for free.

### Changed
- **BREAKING:** Facade management moved behind a single `App.briefly` accessor —
  `App.briefly.configure`, `App.briefly.shortcuts`, `App.briefly.shortcut?` and
  `App.briefly.clear_memos!`. This frees `configure`, `shortcuts`, `shortcut?` and `clear_memos!` for
  use as your own shortcut names; only `briefly`, `inspect` and `to_s` stay reserved on the facade's
  public surface.
- **BREAKING:** `Briefly::Rails::DB#connection`/`#conn` is now an auto-releasing block that forwards to
  `base.with_connection`, yielding the leased connection and releasing it at block exit — the shape of
  `transaction`. It requires a block; the old bare `base.lease_connection` accessor (held on the thread
  and never released, a leak outside a request) is gone, with no compatibility shim. Anyone needing a
  held raw lease calls `lease_connection` on their model directly.
- The DB pack's tests now run against real Active Record on in-memory SQLite, so its Active Record
  calls are verified rather than mocked. `activerecord` and `sqlite3` join `activesupport` as dev-only
  dependencies; the gem still declares no Rails runtime dependency.
- **BREAKING:** `shortcut` now returns the `Briefly::Shortcut` it declares instead of the canonical
  name Symbol. Refine it in place — `shortcut(:x) { ... }.memoize`, `.rescue_from(Error) { fallback }`,
  in any order — so a shortcut's name is never written twice to annotate it. A bodiless `shortcut(:x)`
  fetches an already-declared shortcut (canonical or alias) to refine, raising
  `Briefly::UnknownShortcutError` on an unknown name; it never re-declares. A shortcut's memoization
  and its own error handlers live on the shortcut itself, so refining it after a redeclaration affects
  the declaration you named, exactly as its body does.
- **BREAKING:** The top-level `rescue_from(error_class)` verb is now facade-wide only and takes no
  shortcut names; passing any raises `ArgumentError` pointing at `shortcut(name).rescue_from(...)`.
  Scope a handler to a shortcut by chaining `.rescue_from` onto it. Global `Briefly.rescue_from` is
  unchanged.
- **BREAKING:** the rescue-handler registry is now `Briefly::Rescues` (was
  `Briefly::ErrorRegistry`), reached through `Briefly.rescues` (was `Briefly.errors`) — it holds
  `rescue_from` handlers, not errors. `Briefly.rescues.clear` still resets globally registered
  handlers; the internal `#wide` enumerator is gone, replaced by `#size` for counting registrations.

### Removed
- **BREAKING:** `App.reset!` — use `App.briefly.clear_memos!`. It was a pure alias for `clear_memos!`
  with no internal callers.
- **BREAKING:** The top-level `memoize` DSL verb — chain `.memoize` onto the shortcut `shortcut`
  returns (`shortcut(:x) { ... }.memoize`), or `shortcut(:x).memoize` for one declared elsewhere.
- **BREAKING:** Scoping `rescue_from` by shortcut name on the top-level verb — both single-name
  `rescue_from(Error, :x)` and multi-name `rescue_from(Error, :a, :b)`. Scope on the shortcut instead:
  `shortcut(:x).rescue_from(Error) { ... }`, chaining onto each of several.

## v0.1.0 (2026-07-10)

### Added
- `Briefly.define` builds a facade of real, introspectable, stubbable methods — no `method_missing`.
- `shortcut(canonical, *aliases, &body)` with argument, keyword and block forwarding; predicate and
  bang names; last-declaration-wins overrides. Each shortcut compiles to a real method carrying its
  body's `arity` and parameter kinds, with a `source_location` pointing at the block you declared —
  keyword names are exact, positionals get generated ones (`__p0`, `__r1`, …). A wrong-arity call, a
  missing required keyword and an unknown keyword raise `ArgumentError` at the call site, before any
  `rescue_from` handler is consulted.
- `namespace(name) { ... }` — groups shortcuts behind a child facade, so `App.db.query` works without
  burning root-level names. Takes the whole DSL, including nested namespaces. `clear_memos!` cascades
  into it. `configure` stays atomic across the whole tree: a pass that raises anywhere leaves the root
  and every namespace untouched. A `shortcut` of the same name overrides a namespace and drops the child.
- `memoize` — permanent per-process caching, correct for `nil`/`false`, never caching a rescued fallback.
- `rescue_from` — facade-scoped, facade-wide and global (`Briefly.rescue_from`) handlers whose return
  value becomes the shortcut's value.
- `clear_memos!` / `reset!`, `configure`, `shortcuts`, `shortcut?`, `inspect`.
- Pack protocol: any object responding to `#install(builder, **opts)`. `use` accepts keywords,
  forwarded to the pack's `install`. `Briefly.register(name, pack)` / `Briefly.pack(name)` provide a
  pack registry, so `use "rails/db"` resolves; values may be a pack or a constant path resolved on
  first use, and an unknown name raises `Briefly::UnknownPackError`.
- Method fabrication — the arity, `parameters` and `source_location` each shortcut reports — is
  provided by [candor](https://github.com/svyatov/candor), the sole runtime dependency (candor itself
  has none). Compiled bodies live under `Candor::BODY_PREFIX`; a shortcut may not take a name there.
- `Briefly::Rails` — `config`/`c`, `config_x`/`x`, `env` and its predicates, `root`, `cache`,
  `logger`/`log`, `credentials`/`cred`, `helpers`/`h`, `routes`/`r`, `renderer`, `render`, plus a `db`
  namespace. Nothing in the pack is memoized. Its `Config`, `Env` and `View` groups are usable alone.
- `Briefly::Rails::DB` — `connection`/`conn`, `transaction`/`txn`, `query`. `query` takes positional
  (`query(sql, 1)`) or named (`query(sql, id: 1)`) binds, and passes a bindless statement through
  unsanitized. Takes `base:` (default `"ApplicationRecord"`), resolved on every call so a reloaded
  class is never captured. Memoizes nothing and wires no lifecycle hook, so it works without a booted
  application.
- `Briefly::Rails::Reload` — clears memos via `Rails.application.reloader.to_prepare`.
- RBS signatures in `sig/`.
