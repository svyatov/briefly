# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) and to [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## Unreleased

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
