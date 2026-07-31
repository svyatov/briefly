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
