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

# `rake release` pushes to RubyGems, which requires an MFA OTP. Feed it a fresh code from
# 1Password via GEM_HOST_OTP_CODE, which `gem push` reads.
Rake::Task["release:rubygem_push"].enhance(["fetch_otp"])

task :fetch_otp do
  ENV["GEM_HOST_OTP_CODE"] = `op item get "RubyGems" --account my --otp`.strip
end

task default: %i[rubocop rbs test]
