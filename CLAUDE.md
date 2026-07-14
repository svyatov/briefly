# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

briefly builds a terse facade over an application's most reached-for objects — `App.config`,
`App.render`, `App.logger`. `Briefly.define { ... }` returns a `Facade` whose shortcuts are compiled
onto its singleton class as **real methods**, so `respond_to?`, console tab-completion and test
stubbing all work unaided. There is no `method_missing` anywhere. Method fabrication — the arity, the
`parameters` and the `source_location` a shortcut reports — is [candor](https://github.com/svyatov/candor),
this gem's one runtime dependency, which is itself dependency-free. Rails support lives in an optional,
autoloaded pack.

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

- `lib/briefly/shortcut.rb` — one shortcut: canonical name, aliases, body, source location, memoized
  flag, and its own scoped error handlers. It is the object `shortcut` returns, refined in place by
  `.memoize` and `.rescue_from`; it holds no `Builder` reference
- `lib/briefly/builder.rb` — receives the DSL (`shortcut`, `rescue_from`, `use`, `namespace`),
  collects shortcuts, validates them in `compile!`
- `lib/briefly/facade.rb` — hands shortcuts to `Candor.define`; owns the memo store, the namespace
  children and error dispatch (a shortcut's own handlers first, then facade-wide, then global)
- `lib/briefly/rescues.rb` — the facade-wide and global `rescue_from` handlers (one registry
  per facade plus one global); a shortcut's own handlers live on the `Shortcut`, not here

Every shortcut becomes a real method through `Candor.define(singleton_class, name, aliases:, via:
:__call, parameters:, source_location:, body:)`. Candor installs the body privately under
`Candor::BODY_PREFIX`, reads that compiled method's `parameters`, and compiles a same-arity dispatch
onto every name; each call lands in `Facade#__call`, which is where memoization and `rescue_from` live.
Nothing in this repo renders method source any more — see candor's own README and invariants.

`lib/briefly/rails.rb` (autoloaded) is an umbrella over the packs nested in it — `Config`, `Env`,
`View` — plus `lib/briefly/rails/db.rb` and `lib/briefly/rails/reload.rb`. A **pack** is any object
responding to `#install(builder, **opts)` — that is the entire protocol. `Briefly.register` maps a
short name to a pack or a constant path, so `use "rails/db"` resolves; the registry is the only
source of truth, there is no inflection.

A **namespace** is a child `Facade` reached by a real method, so `App.db.query` needs no
`method_missing`. Children thread through `Builder.new(facade, defs, children)` and out of
`compile!`, the same seam the shortcuts use.

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
- **Reflection parity is candor's, not ours.** Reading the *compiled* body's `parameters` rather than
  the Proc's, rendering off a parameter's kind rather than its name, the unpassed-optional sentinel,
  the collision-free prefix that keeps a keyword named `__u` or `binding` from capturing the generated
  source, and dropping unpassed optionals by branching rather than accumulating — all of it lives in
  `candor`, is pinned by candor's tests, and must be changed there. Do not reintroduce any of it here.
- **`Candor.define` is passed `body:` and three keywords that each earn their place.** `via: :__call` routes
  every shortcut through the memo and rescue layer. `source_location:` because `namespace` rewrites it —
  its body is a `proc { child }` literal in `builder.rb`, and the compiled method must point at the
  caller's block. `aliases:` so every name shares one dispatch and one canonical name. There is
  deliberately **no** `parameters: []` for a memoized shortcut: `compile!` already refuses a memoized
  body that takes an argument, so the override is unreachable, and a mutation deleting it fails no test.
- **`Facade` gains no private helper *for compilation*.** `Facade::RESERVED` is built from
  `private_instance_methods(false)`, so every private method takes one name out of the shortcut
  namespace. Two kinds of private method are not the same: an *accidental compilation helper* is still
  forbidden — `__define` delegates to candor rather than compiling for exactly this reason — but the
  four `__`-prefixed *management* methods (`__shortcuts`, `__shortcut?`, `__clear_memos!`, `__configure`)
  are deliberate. They are the surface behind the single public `briefly` accessor, reached by
  `Control` via `send`, and hiding all four behind one door is why only `briefly` — not five names —
  leaves the shortcut namespace. Every private name being `__`-prefixed is what keeps it unreachable as
  a shortcut. Pinned by `test_the_facade_gained_no_private_helper` (the exact list) and its sibling
  `test_every_reserved_private_name_is_prefixed_and_so_unreachable_as_a_shortcut`.
- **A shortcut name may not start with `Candor::BODY_PREFIX`, and `Builder` says so in `validate_name!`, as each name is declared.**
  Candor refuses the name too, but as an `ArgumentError` and only once `__commit` is already installing —
  too late for the tree-wide atomicity `configure` promises.
- **A facade-wide `rescue_from(StandardError)` also catches the user's own bugs.** A `NoMethodError`
  from a typo inside a body is indistinguishable, at the point `__handle` runs, from the failure the
  handler was written for. Narrowing the `rescue` in `__call` cannot separate them without backtrace
  inspection, so this is **documented, not fixed** — see the README's `rescue_from` callout. Do not
  "solve" it by guessing at the error's origin. A bad *call from outside the facade* is a different
  matter and is fixed: every shortcut compiles to a method carrying its body's arity, so a wrong-arity
  call, a missing required keyword and an unknown keyword all raise before that shortcut's `__call` is
  entered, and its handlers never observe them. This does not extend to one body calling another: the
  callee raises at a call site lexically inside the caller's body, hence inside the *caller's* `__call`
  rescue, so the caller's handler swallows it. Pinned by
  `test_a_wrong_arity_call_between_shortcuts_is_seen_by_the_callers_handler`.
- **`__call` looks the shortcut up outside its own `rescue`.** An internal `KeyError` must never be
  laundered into a user's fallback.
- **`Rescues#add` rebinds `@entries` under the mutex.** `[*@entries, entry]` is a read, a build
  and an assign; two threads that read the same array each write their own successor, and the loser's
  handlers vanish — not one entry, but everything it appended since its snapshot. Reads stay lock-free
  against the frozen array; only writers serialize. Scale alone does not pin this: with the
  `synchronize` deleted, 4,000 concurrent registrations lost nothing in 20 runs, because MRI rarely
  preempts inside so short a window. `test_add_holds_the_mutex_while_rebinding_entries` asserts the
  exclusion directly instead of racing for it.
- **`Builder` deep-copies the facade's shortcuts.** A `configure` pass that raises must leave the
  live facade exactly as it was — `Hash#dup` alone shares each `Shortcut`'s `aliases` and `rescues`
  arrays. The namespace children hash is copied for the same reason: a pass that raises must not leave
  a new child reachable.
- **`namespace` collects its child's pass, it does not run it.** `compile!` recurses to validate the
  whole tree; only then does `__commit` install any of it, children first. Calling `child.configure`
  inline instead commits eagerly, so a raise later in the parent's pass — or in a *sibling* namespace —
  leaves an already-reachable child half-updated. Atomicity is tree-wide, not per-facade.
- **One pending `Builder` per namespace name.** `namespace(:db)` twice in one pass must extend the child,
  not replace it — that is how an app adds to a namespace a pack declared. A second `__prepare` would
  snapshot the child's *committed* defs and drop the first block's work on commit.
- **`namespace` reuses its child across passes.** A fresh `Facade.new` per `configure` would drop the
  child's memos and orphan any `to_prepare` callback closed over the old child.
- **`purge` drops children, and grants `except:` no exemption.** A namespace is a shortcut returning its
  child, so redeclaring the name — canonical or as another shortcut's alias — must drop the child, or
  `clear_memos!` keeps walking a facade nothing can reach. `namespace` re-registers its own child right
  after its `shortcut` call; that is what the missing exemption is for. Exempting `except:` instead makes
  the drop a no-op, since `shortcut(:db)` purges with `except: :db`.
- **`clear_memos!` cascades into namespace children.** One `Reload` on the root clears the whole tree,
  including a namespace holding no Rails pack. Without this, memoizing inside a namespace pins a value
  across reloads, and no test but `test_clear_memos_cascades_into_namespaces` notices.
- **`Briefly::Rails::DB#select` reads through `select_all`; `#query` runs through `exec_query`.**
  `select` and `query` share one `install`-local closure that differs by exactly the adapter method it
  `public_send`s. `select_all` is the read-optimized path Rails recommends for a raw SELECT, returning
  an `ActiveRecord::Result` without clearing the query cache; `exec_query` is the general form that runs
  writes and DDL too. The split is name and cache-path, not a runtime read/write guard — `select_all`
  still executes a write if handed one. Pinned by a matched pair,
  `test_select_reads_through_select_all_not_exec_query` and `test_query_runs_through_exec_query_not_select_all`,
  which spy the connection `with_connection` yields so a revert to the wrong method fails rather than
  staying green (row/shape assertions pass under either).
- **`Briefly::Rails::DB#connection`/`#conn` is a bare `with_connection` passthrough, structurally the
  `transaction` line.** Body `{ |**opts, &blk| model.call.with_connection(**opts, &blk) }` — it yields
  the leased connection, auto-releases at block exit, and forwards every keyword, so the whole
  `with_connection` surface (`prevent_permanent_checkout:` today) stays reachable. There is deliberately
  no bare-lease fallback and no `lease`/`release` pair: a held lease leaks outside a request, and the
  pack ships no `release` to pair it. A call with no block raises `LocalJumpError` from Rails' own
  `with_connection` — that *is* the "requires a block" contract, so no explicit guard code is needed.
  Auto-release holds even when the block raises: Rails' `with_connection` ensures the release, so a
  forgotten guard can't leak the lease. Pinned by
  `test_connection_yields_a_live_connection_and_returns_the_block_value`,
  `test_connection_forwards_keywords_to_with_connection`, `test_connection_without_a_block_raises`, and
  `test_connection_releases_the_lease_when_the_block_raises`.
- **Neither `Briefly::Rails::DB#select` nor `#query` may sanitize a bindless statement.**
  `sanitize_sql_array` falls through to a `statement % values` branch that raises on any literal `%` —
  `... like '%ada%'`. The bindless-skip lives once, in the shared closure, and covers both shortcuts.
- **Neither `Briefly::Rails::DB#select` nor `#query` declares a keyword parameter.** Accepting none is
  what makes Ruby pack `select(sql, id: 1)` into `binds` as a trailing Hash, which is how named binds
  reach `sanitize_sql_array`. A `**opts` would swallow them and send the statement to the database
  unbound. The `|sql, *binds|` shape is shared by both; changing either to take `**opts` breaks binds.
- **`Briefly::Rails::DB#connected_to` forwards `**opts` to the resolved base; `#reading` / `#writing`
  pin the role after the splat.** `connected_to` is a faithful passthrough — role, shard, prevent_writes,
  custom roles — so the whole Rails multi-database surface is reachable. `reading`/`writing` are sugar:
  `connected_to(**opts, role: :reading, &blk)` puts the pinned role *after* `**opts` so a `role:` passed
  through can't win, while `shard:`/`prevent_writes:` still forward. Rails allows `connected_to` only on
  `ActiveRecord::Base` or an abstract class — the one that declared `connects_to` — so `base` must be
  such a class; on a concrete model it raises `NotImplementedError`. Pinned by
  `test_reading_and_writing_pin_their_role` and `test_connected_to_forwards_arbitrary_roles`.
- **`Briefly::Rails::DB` reaches the pool only through `with_connection`, never `connection`.** Every
  shortcut that touches a connection (`conn`, `select`, `query`) routes through `with_connection`;
  `.connection` is soft-deprecated and raises under `ActiveRecord.permanent_connection_checkout =
  :disallowed` — set in the real-AR test harness, so the pack's `.connection`-avoidance is pinned rather
  than assumed. Pinned by `test_the_pack_never_reaches_for_the_deprecated_connection_method`.
- **Inside `lib/briefly/rails*.rb` the framework is always `::Rails`.** Bare `Rails` resolves to
  `Briefly::Rails`. `test/briefly/rails_pack_test.rb` lexes the source to enforce this, and has
  fixture tests proving the check bites. It globs the pack files rather than listing them, so a new
  pack file cannot join the tree without joining the check.
- **Every shipped pack is registered as a constant path String, never the constant.** Naming
  `Briefly::Rails::DB` in the `@packs` table would resolve it at load and defeat `autoload :Rails`.

## Testing

minitest, no RSpec. No dummy Rails app. The forwarding packs (config, env, view, error, instrument)
run against a hand-rolled `::Rails` double, and the reload test against a real
`Class.new(ActiveSupport::Reloader)`, so `to_prepare`/`prepare!` semantics are genuinely exercised.
The DB pack is the exception: it runs against real Active Record on in-memory SQLite
(`test/support/active_record.rb`), so `with_connection`, `select_all`, `exec_query`,
`sanitize_sql_array` and `connected_to` are exercised as the framework really behaves, not as a double
would echo them. `activesupport`, `activerecord` and `sqlite3` are the Rails-side dev dependencies; the
gem still declares no Rails runtime dependency.

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
