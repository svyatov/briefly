# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) and to [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## Unreleased

### Added
- `namespace(name) { ... }` — groups shortcuts behind a child facade, so `App.db.query` works without burning root-level names. Takes the whole DSL, including nested namespaces. `clear_memos!` cascades into it. `configure` stays atomic across the whole tree: a pass that raises anywhere leaves the root and every namespace under it untouched. A `shortcut` of the same name overrides a namespace and drops the child.
- `use` accepts keywords, forwarded to the pack's `install`, e.g. `use Briefly::Rails::DB, base: "SecondaryApplicationRecord"`.
- `Briefly.register(name, pack)` and `Briefly.pack(name)` — a pack registry, so `use "rails/db"` works. Values may be a pack or a constant path resolved on first use. An unregistered name, or one naming a path that does not resolve, raises `Briefly::UnknownPackError`; a `NameError` raised *inside* a pack as it loads propagates untouched.
- `Briefly::Rails::DB` — `connection`/`conn`, `transaction`/`txn`, `query`. `query` takes positional (`query(sql, 1)`) or named (`query(sql, id: 1)`) binds, and passes a bindless statement through unsanitized. Takes `base:` (default `"ApplicationRecord"`), resolved on every call so a reloaded class is never captured. Memoizes nothing and wires no lifecycle hook, so it works without a booted application.
- `Briefly::Rails::Config`, `Briefly::Rails::Env` and `Briefly::Rails::View` — the umbrella pack's groups, now usable on their own.

### Changed
- `Briefly::Rails` mounts `Briefly::Rails::DB` under a new `db` namespace, so its shortcuts arrive as `App.db.*` rather than at the root. The umbrella now claims one further root-level name, `db`; declare your own `shortcut(:db)` *after* `use Briefly::Rails` to keep it.

## v0.1.0 (2026-07-09)

### Added
- `Briefly.new` builds a facade of real, introspectable, stubbable methods — no `method_missing`.
- `shortcut(canonical, *aliases, &body)` with argument, keyword and block forwarding; predicate and bang names; last-declaration-wins overrides.
- `memoize` — permanent per-process caching, correct for `nil`/`false`, never caching a rescued fallback.
- `rescue_from` — facade-scoped, facade-wide and global (`Briefly.rescue_from`) handlers whose return value becomes the shortcut's value.
- `clear_memos!` / `reset!`, `configure`, `shortcuts`, `shortcut?`, `inspect`.
- Pack protocol: any object responding to `#install(builder)`.
- `Briefly::Rails` — `config`/`c`, `config_x`/`x`, `env` and its predicates, `root`, `cache`, `logger`/`log`, `credentials`/`cred`, `helpers`/`h`, `routes`/`r`, `renderer`, `render`. Nothing in the pack is memoized.
- `Briefly::Rails::Reload` — clears memos via `Rails.application.reloader.to_prepare`.
- RBS signatures in `sig/`.
