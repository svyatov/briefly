# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

briefly builds a terse facade over an application's most reached-for objects — `App.config`,
`App.render`, `App.logger`. `Briefly.new { ... }` returns a `Facade` whose shortcuts are compiled
onto its singleton class as **real methods**, so `respond_to?`, console tab-completion and test
stubbing all work unaided. There is no `method_missing` anywhere, and the gem has **zero runtime
dependencies**. Rails support lives in an optional, autoloaded pack.

## Common Commands

```bash
# Run linting, RBS validation and tests (default rake task)
bundle exec rake

# Tests only
bundle exec rake test

# A single test file / a single test method
bundle exec ruby -Itest test/briefly/memoize_test.rb
bundle exec ruby -Itest test/briefly/memoize_test.rb -n test_body_runs_once

# Enforce 100% line coverage (SimpleCov is off unless COVERAGE is set)
COVERAGE=true bundle exec rake

# Linter, RBS, docs
bundle exec rake rubocop
bundle exec rake rbs
bundle exec rake yard:stats        # fails unless 100% of the public API is documented

# Test against another Rails version (Gemfile reads RAILS_VERSION; "edge" tracks rails/rails)
rm -f Gemfile.lock && RAILS_VERSION=7.2 bundle install && RAILS_VERSION=7.2 bundle exec rake test

# Release (update version.rb first); OTP is fetched from 1Password
bundle exec rake release
```

## Architecture

Four core files, each with one job:

- `lib/briefly/definition.rb` — one shortcut declaration: canonical name, aliases, body, memoized flag
- `lib/briefly/builder.rb` — receives the DSL (`shortcut`, `memoize`, `rescue_from`, `use`), collects
  definitions, validates them in `compile!`
- `lib/briefly/facade.rb` — compiles definitions onto its singleton class; owns the memo store and
  error dispatch
- `lib/briefly/error_registry.rb` — `rescue_from` handlers, one instance per facade plus one global

`lib/briefly/rails.rb` (autoloaded) and `lib/briefly/rails/reload.rb` are packs. A **pack** is any
object responding to `#install(builder)` — that is the entire protocol.

Signatures live in `sig/`. Shortcuts are compiled at runtime, so RBS cannot see them; `sig/` types
the static surface only. There is no Steep target and no `rbs test` — CONTRIBUTING.md's **Types**
section says why, and it is not an oversight. `sig/` is verified by review.

## Invariants

Break one of these and the gem is unsafe. Each is pinned by a test — find it before changing the code.

- **A shortcut body is compiled to a real private singleton method, never `instance_exec`'d.**
  `instance_exec` spends the block slot on the body, so the caller's block is silently dropped and
  `App.render(:x) { }` breaks. Compilation also makes arity strict, which is a feature.
- **The memo lock is a reentrant `Monitor`, not a `Mutex`.** A memoized body may call another
  memoized shortcut; a `Mutex` deadlocks there. One lock for the whole facade — per-shortcut locks
  turn a bounded `SystemStackError` on a cyclic shortcut graph into a permanent silent deadlock.
- **The copy-on-write memo merge must re-read `@__memos` after the body runs.** Merging into a
  snapshot captured before `yield` discards any memo a nested shortcut wrote.
- **A rescued fallback is never memoized.** The body raises inside `__memo`'s block, so nothing is
  stored and the transient failure is retried. This does not compose: memoizing a shortcut whose
  body *reads* a rescue-backed shortcut pins the fallback. Documented in the README.
- **`__handle` calls `Kernel.raise`, not bare `raise`.** A bare `raise` under an implicit receiver
  could dispatch into a shortcut named `raise`, recursing until `SystemStackError`.
- **A facade-wide `rescue_from(StandardError)` also catches the user's own bugs.** An `ArgumentError`
  from a wrong-arity call and a `NoMethodError` from a typo inside a body are indistinguishable, at
  the point `__handle` runs, from the failure the handler was written for. Narrowing the `rescue` in
  `__call` cannot separate them without backtrace inspection, so this is **documented, not fixed** —
  see the README's `rescue_from` callout. Do not "solve" it by guessing at the error's origin.
  Memoized shortcuts are the one exception: they compile to zero-argument methods, so an arity error
  raises before `__call` is entered.
- **`__call` looks the definition up outside its own `rescue`.** An internal `KeyError` must never be
  laundered into a user's fallback.
- **`Builder` deep-copies the facade's definitions.** A `configure` pass that raises must leave the
  live facade exactly as it was — `Hash#dup` alone shares the `aliases` arrays.
- **Inside `lib/briefly/rails*.rb` the framework is always `::Rails`.** Bare `Rails` resolves to
  `Briefly::Rails`. `test/briefly/rails_pack_test.rb` lexes the source to enforce this, and has
  fixture tests proving the check bites.

## Testing

minitest, no RSpec. No dummy Rails app: the pack tests run against a hand-rolled `::Rails` double,
and the reload test against a real `Class.new(ActiveSupport::Reloader)`, so `to_prepare`/`prepare!`
semantics are genuinely exercised. `activesupport` is the only Rails-side dev dependency.

Coverage must stay at 100% (`COVERAGE=true bundle exec rake`).

Guard tests that assert an absence (no bare `Rails`, no memo tearing) must themselves be tested
against a fixture that violates the rule. A guard that cannot fail is not a guard.

## Commit Convention

This project follows [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).

Format: `<type>[optional scope]: <description>`

| Type | Description | Version bump |
|------|-------------|--------------|
| `feat` | New feature | MINOR |
| `fix` | Bug fix | PATCH |
| `docs` | Documentation only | — |
| `style` | Formatting, whitespace | — |
| `refactor` | Code change (no feature/fix) | — |
| `perf` | Performance improvement | — |
| `test` | Adding/fixing tests | — |
| `build` | Build system or dependencies | — |
| `ci` | CI configuration | — |
| `chore` | Maintenance tasks | — |

Use `!` after the type or add a `BREAKING CHANGE:` footer for breaking changes; they trigger a MAJOR
version bump.

## Changelog Format

This project follows [Keep a Changelog v1.1.0](https://keepachangelog.com/en/1.1.0/).

Allowed categories in **required order**:

1. **Added** — new features
2. **Changed** — changes to existing functionality
3. **Deprecated** — soon-to-be removed features
4. **Removed** — removed features
5. **Fixed** — bug fixes
6. **Security** — vulnerability fixes

Rules:
- Categories must appear in the order listed above within each release section
- Each category must appear **at most once** per release section — append to an existing category
  rather than creating a duplicate
- Do NOT use non-standard categories like "Updated", "Internal", or "Breaking changes"
- Breaking changes get a **BREAKING:** prefix within the relevant category (typically Changed or Removed)

`CHANGELOG.md` must stay current on every feature branch. After each commit, ensure the `## Unreleased`
section at the top accurately reflects all user-facing changes on the branch. The unreleased section
describes the **net result** compared to the last release, not a history of intermediate steps — when a
later change supersedes an earlier one, update or remove the stale bullet.

## Documentation Style

All classes and methods must have YARD documentation. Follow these conventions:

- Always leave a **blank line** between the main description and `@` attributes (params, return, etc.)
- Document all public methods with description, params, and return types
- Document all private methods with params and return types; add a description for complex logic
- **Omit descriptions that just repeat the code** — if the name and signature make it obvious, include
  only the `@param` / `@return` tags
- Comments inside `facade.rb` and `builder.rb` explain *why* a metaprogramming choice is load-bearing.
  They are the invariants above, restated where the code lives. Do not delete them as noise.

## Releasing a New Version

This project follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

1. Update `lib/briefly/version.rb`
2. Update `CHANGELOG.md`: change `## Unreleased` to `## vX.Y.Z (YYYY-MM-DD)` and add a new empty
   `## Unreleased` section
3. Commit: `chore: bump version to X.Y.Z`
4. Release: `bundle exec rake release`
