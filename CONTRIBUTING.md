# Contributing

## Setup

```sh
bin/setup            # bundle install
bundle exec rake     # rubocop + rbs validate + minitest
bin/console          # irb with briefly loaded
```

Test against a specific Rails version the way CI does. Each file under `gemfiles/` pins one Rails
line and evaluates the root `Gemfile`, and the three released lines commit a lockfile beside theirs:

```sh
BUNDLE_GEMFILE=gemfiles/rails_7.2.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_7.2.gemfile bundle exec rake
```

`gemfiles/rails_edge.gemfile` tracks `rails/rails` HEAD and commits no lockfile, so it resolves fresh
every time. That is why the edge and `ruby-head` CI legs are advisory rather than blocking.

Changing the root `Gemfile` means regenerating all four lockfiles, or CI fails the frozen install
before it runs a test. Regenerate them on Ruby 3.2, the lowest version the gemspec supports:

```sh
mise x ruby@3.2 -- bundle lock
for v in 7.2 8.0 8.1; do BUNDLE_GEMFILE="gemfiles/rails_$v.gemfile" mise x ruby@3.2 -- bundle lock; done
```

The Ruby version matters. A lockfile resolved on 4.0 can pin a gem that requires 3.3 or newer, and
the 3.2 CI legs then fail the frozen install rather than re-resolving, which is the whole point of
freezing. Resolving on the oldest supported Ruby picks versions every leg in the matrix can install.

Only `activesupport` is needed: the Rails packs are exercised against a real
`ActiveSupport::Reloader` subclass and a hand-rolled `::Rails` double. There is no dummy app.

## Code style

- Ruby 3.2+, two-space indent, 120 columns, `bundle exec rubocop` clean.
- **One runtime dependency, `candor`, and no others.** It is itself dependency-free; do not add a second.
- Inside `lib/briefly/rails*.rb` the framework is always `::Rails`, because a bare `Rails` resolves to
  `Briefly::Rails`. A test enforces this.
- Line coverage must stay at 100% (`COVERAGE=true bundle exec rake test`).
- Every public method carries YARD documentation (`bundle exec rake yard:stats`).
- Update `sig/` alongside `lib/`; `bundle exec rake rbs` must pass.

## Types

`bundle exec rake rbs` runs `rbs validate`, which checks that the signatures parse and resolve. It
does **not** check them against `lib/`. Two tools that would, and why neither is wired up:

**`RBS::Test`** rewraps every block it sees, which changes `Proc#arity`, and `memoize` refuses
argument-taking bodies based on exactly that. Enabling it fails 42 tests that are not broken.

**Steep** works, but pays for less than it looks like. Against the current tree it reports two
errors, both signature papercuts rather than defects (`Struct[untyped]` gives `Entry` no positional
`.new`, and a tuple cannot be splatted into positional parameters), plus seven warnings that must be
suppressed to get a green run: five `UnannotatedEmptyCollection` on `{}.freeze` / `[].freeze` whose
ivars are already typed in `sig/`, and two `BlockTypeMismatch` on `define_method(&proc)`, because
stdlib RBS types that block as `^ [self: top] -> untyped` and no `Proc` value satisfies it.
Compiling procs into methods is the whole gem.

More decisive: Steep silently skips `lib/briefly/rails.rb` and `lib/briefly/rails/reload.rb`. They
never appear in `steep stats`, and an injected `builder.no_such_method_at_all` in the pack goes
unreported while the same mistake in a fresh `lib/briefly/zzz.rb` is caught. Whatever the cause, the
one file with real framework coupling, where a bare `Rails` silently resolves to `Briefly::Rails`,
is the one file Steep does not cover. A lexer test in `test/briefly/rails_pack_test.rb` covers it
instead.

So `sig/` is verified by review, not by a checker. Keep it small, and change it in the same commit
as the code it describes.

## What an acceptable change looks like

[CLAUDE.md](CLAUDE.md) is the standard a change is measured against. It is written for coding agents
and it is tracked for exactly this reason: its Invariants section lists the properties that make the
gem safe, each one pinned by a test, and its Testing, Documentation Style and Changelog Format
sections say the rest. Read the invariants before changing anything under `lib/`. Every one of them
has a test you can find first, and breaking one silently is the failure mode this gem is most
exposed to.

A change that adds or alters behavior arrives with a test. Coverage is enforced at 100%, so an
untested branch fails CI rather than reaching review, but the number is a floor and not the point:
the test should pin the behavior you are claiming, in the way the existing tests pin theirs. A guard
test that asserts an absence needs a fixture proving the guard can fail.

## Commits and pull requests

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

Fork the repository, branch off `main`, and open a pull request against `main`. Pull requests are
squash merged, so the branch's history is yours to keep messy; the pull request title is what lands
on `main` and should be the Conventional Commit line.

Before opening one: `bundle exec rake` is green, coverage is 100%, and `CHANGELOG.md`'s
`## Unreleased` section reflects the net user-facing change since the last release rather than a
history of what you tried. The pull request template asks for the rest.

## Deprecating and removing

A public item, meaning anything the README's Versioning section covers, gets a released deprecation
before it is removed. Ship the deprecation in one release with the old path still working and a
runtime warning that names the replacement and the earliest version the removal can land in, then
remove it in a later release. While the version is below `1.0.0` both of those are MINOR bumps.

The v0.2.0 release predates this policy and removed three things without one: `App.reset!`, the
top-level `memoize` verb, and name-scoped `rescue_from`. The changelog names the replacement for
each, which is what a deprecation warning would have said, a release earlier.

## Releases

Nothing publishes from a laptop. A release is a signed tag pushed to `main`, which starts
`.github/workflows/release.yml`: it checks the tag against `Briefly::VERSION`, runs the suite, builds
the gem in a job holding no credential, and then waits for a person to approve the `release`
environment before the publish job runs at all. That job authenticates to rubygems.org through OIDC,
so no API key exists to leak, and it signs the exact bytes the build job produced.

`bundle exec rake release` prints those steps and exits without publishing.

## Who decides

Leonid Svyatov ([@svyatov](https://github.com/svyatov)) maintains `briefly`, reviews and merges every
change, and cuts every release. There is no second maintainer and no succession arranged. If that
ever changes, this section is where it will say so.
