# frozen_string_literal: true

require_relative "lib/briefly/version"

Gem::Specification.new do |spec|
  spec.name = "briefly"
  spec.version = Briefly::VERSION
  spec.authors = ["Leonid Svyatov"]
  spec.email = ["leonid@svyatov.com"]

  spec.summary = "A terse, curated facade over your application's most reached-for objects."
  spec.description = "Declare one facade object per application area and reach your framework, config and " \
                     "clients through short, real, introspectable methods. Zero runtime dependencies, " \
                     "correct under Puma and Rails code reloading, with a batteries-included Rails pack."
  spec.homepage = "https://github.com/svyatov/briefly"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2.0"

  spec.require_paths = ["lib"]
  spec.files = Dir["lib/**/*.rb"] + Dir["sig/**/*"] +
               %w[.yardopts CHANGELOG.md LICENSE.txt README.md briefly.gemspec]

  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/briefly"
  spec.metadata["source_code_uri"] = "https://github.com/svyatov/briefly"
  spec.metadata["changelog_uri"] = "https://github.com/svyatov/briefly/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/svyatov/briefly/issues"
end
