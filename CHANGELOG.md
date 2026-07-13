# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) and to [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## Unreleased

### Changed
- **BREAKING:** Facade management moved behind a single `App.briefly` accessor —
  `App.briefly.configure`, `App.briefly.shortcuts`, `App.briefly.shortcut?` and
  `App.briefly.clear_memos!`. This frees `configure`, `shortcuts`, `shortcut?` and `clear_memos!` for
  use as your own shortcut names; only `briefly`, `inspect` and `to_s` stay reserved on the facade's
  public surface.

### Removed
- **BREAKING:** `App.reset!` — use `App.briefly.clear_memos!`. It was a pure alias for `clear_memos!`
  with no internal callers.

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
