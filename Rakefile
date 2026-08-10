# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "rubocop/rake_task"
require "yard"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

RuboCop::RakeTask.new

RBS_LIBS = %w[monitor].freeze

desc "Validate RBS signatures"
task :rbs do
  sh "rbs #{RBS_LIBS.map { |lib| "-r #{lib}" }.join(" ")} -I sig validate"
end

# The Ruby the gemspec floors at. A lockfile resolved on a newer Ruby can pin a gem that requires
# 3.3 or newer, and the 3.2 legs then fail the frozen install rather than re-resolving.
LOCK_RUBY = "3.2"

# Dependabot refreshes Gemfile.lock only. It matches lockfiles by the name beside a Gemfile it
# fetched, and `gemfiles/rails_8.0.gemfile.lock` is not such a name, so the matrix locks have to be
# refreshed by hand: run this whenever a Dependabot pull request touches the root lock.
desc "Refresh every committed lockfile (root Gemfile plus the Rails matrix gemfiles)"
task "lock:refresh" do
  unless RUBY_VERSION.start_with?("#{LOCK_RUBY}.")
    abort "Resolve on Ruby #{LOCK_RUBY}, not #{RUBY_VERSION}: " \
          "mise x ruby@#{LOCK_RUBY} -- bundle exec rake lock:refresh"
  end

  # with_unbundled_env, because `bundle exec rake` exports BUNDLE_GEMFILE and the nested `bundle`
  # restores it from BUNDLER_ORIG_BUNDLE_GEMFILE, discarding the override below and writing every
  # gemfile's resolution into the root Gemfile.lock.
  Bundler.with_unbundled_env do
    sh "bundle lock"
    Dir["gemfiles/*.gemfile"].each do |gemfile|
      # rails_edge.gemfile tracks rails/rails HEAD, so it ships no lockfile and resolves fresh.
      next if gemfile.end_with?("rails_edge.gemfile")

      sh "BUNDLE_GEMFILE=#{gemfile} bundle lock"
    end
  end
end

YARD::Rake::YardocTask.new

namespace :yard do
  desc "Fail unless 100% of the public API is documented"
  task :stats do
    out = `yard stats --list-undoc`
    puts out
    abort "Undocumented public API found" unless out.include?("100.00% documented")
  end
end

# Publishing happens in CI, triggered by a tag, and authenticates through RubyGems OIDC, so no
# credential exists on any developer machine to push with. Bundler's own release tasks do push from
# here, so they are replaced with the instruction rather than left reachable: a working local publish
# is one distracted evening away from shipping an uncommitted working tree.
%w[release release:rubygem_push release:source_control_push].each do |name|
  Rake::Task[name].clear if Rake::Task.task_defined?(name)
end

desc "Explain how a release actually happens"
task :release do
  abort <<~MESSAGE
    Releases are cut by pushing a tag, not from here.

      1. Set Briefly::VERSION in lib/briefly/version.rb
      2. Move CHANGELOG.md's `## Unreleased` heading to `## vX.Y.Z (YYYY-MM-DD)` and open a new one
      3. Commit, and merge to main through a pull request
      4. git tag -s vX.Y.Z -m "Version X.Y.Z" && git push origin vX.Y.Z

    The tag push starts .github/workflows/release.yml, which tests, builds, and then waits for you
    to approve the `release` environment before anything reaches rubygems.org.
  MESSAGE
end

task default: %i[rubocop rbs test]
