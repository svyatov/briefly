# frozen_string_literal: true

source "https://rubygems.org"

# Runtime dependencies are declared in the gemspec.
gemspec

gem "irb", require: false # for bin/console (a bundled gem since Ruby 3.4)
gem "rake", "~> 13.4"

gem "minitest", "~> 6.0"

# The forwarding packs are exercised against a real ActiveSupport::Reloader and a hand-rolled ::Rails
# double; the DB pack runs against real Active Record on in-memory SQLite — no railties, no dummy app.
# activerecord tracks the same version as activesupport so the matrix stays coherent. CI pins per cell.
if ENV["RAILS_VERSION"] == "edge"
  # The glob spans activemodel too: activerecord@HEAD depends on it at the same unreleased version, so
  # bundler must discover that sibling's gemspec from the repo to resolve activerecord from git.
  rails_glob = "{activesupport,activemodel,activerecord}/*.gemspec"
  gem "activerecord", github: "rails/rails", glob: rails_glob
  gem "activesupport", github: "rails/rails", glob: rails_glob
elsif ENV["RAILS_VERSION"]
  gem "activerecord", "~> #{ENV["RAILS_VERSION"]}.0"
  gem "activesupport", "~> #{ENV["RAILS_VERSION"]}.0"
else
  gem "activerecord"
  gem "activesupport"
end

gem "sqlite3", ">= 2.1"

gem "rubocop", "~> 1.88"
gem "rubocop-minitest", "~> 0.39"

gem "rbs", "~> 4.0", require: false

gem "yard", "~> 0.9", require: false

gem "simplecov", "~> 0.22", require: false
gem "simplecov_json_formatter", "~> 0.1", require: false
