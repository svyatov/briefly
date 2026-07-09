# Contributing

## Setup

```sh
bin/setup            # bundle install
bundle exec rake     # rubocop + rbs validate + minitest
bin/console          # irb with briefly loaded
```

Test against a specific Rails version the way CI does:

```sh
rm -f Gemfile.lock && RAILS_VERSION=7.2 bundle install && bundle exec rake
```

Only `activesupport` is needed: the Rails packs are exercised against a real
`ActiveSupport::Reloader` subclass and a hand-rolled `::Rails` double. There is no dummy app.

## Code style

- Ruby 3.2+, two-space indent, 120 columns, `bundle exec rubocop` clean.
- **No runtime dependencies.** Ever. The gemspec must stay empty of them.
- Inside `lib/briefly/rails*.rb` the framework is always `::Rails` — a bare `Rails` resolves to
  `Briefly::Rails`. A test enforces this.
- Line coverage must stay at 100% (`COVERAGE=true bundle exec rake test`).
- Every public method carries YARD documentation (`bundle exec rake yard:stats`).
- Update `sig/` alongside `lib/`; `bundle exec rake rbs` must pass.

## Types

`bundle exec rake rbs` runs `rbs validate`, which checks that the signatures parse and resolve. It
does **not** check them against `lib/`. Two tools that would, and why neither is wired up:

**`RBS::Test`** rewraps every block it sees, which changes `Proc#arity` — and `memoize` refuses
argument-taking bodies based on exactly that. Enabling it fails 42 tests that are not broken.

**Steep** works, but pays for less than it looks like. Against the current tree it reports two
errors, both signature papercuts rather than defects — `Struct[untyped]` gives `Entry` no positional
`.new`, and a tuple cannot be splatted into positional parameters — plus seven warnings that must be
suppressed to get a green run: five `UnannotatedEmptyCollection` on `{}.freeze` / `[].freeze` whose
ivars are already typed in `sig/`, and two `BlockTypeMismatch` on `define_method(&proc)`, because
stdlib RBS types that block as `^ [self: top] -> untyped` and no `Proc` value satisfies it.
Compiling procs into methods is the whole gem.

More decisive: Steep silently skips `lib/briefly/rails.rb` and `lib/briefly/rails/reload.rb`. They
never appear in `steep stats`, and an injected `builder.no_such_method_at_all` in the pack goes
unreported while the same mistake in a fresh `lib/briefly/zzz.rb` is caught. Whatever the cause, the
one file with real framework coupling — where a bare `Rails` silently resolves to `Briefly::Rails` —
is the one file Steep does not cover. A lexer test in `test/briefly/rails_pack_test.rb` covers it
instead.

So `sig/` is verified by review, not by a checker. Keep it small, and change it in the same commit
as the code it describes.

## Commits and pull requests

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

Before opening a PR: tests pass, coverage is 100%, `bundle exec rake` is green, and `CHANGELOG.md`'s
`## Unreleased` section reflects the net user-facing change.
