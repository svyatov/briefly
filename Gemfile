# frozen_string_literal: true

source "https://rubygems.org"

# Runtime dependencies are declared in the gemspec (there are none).
gemspec

gem "irb", require: false # for bin/console (a bundled gem since Ruby 3.4)
gem "rake", "~> 13.4"

gem "minitest", "~> 6.0"

# The Rails packs are exercised against a real ActiveSupport::Reloader and a hand-rolled ::Rails
# double — no railties, no dummy app. CI pins this per matrix cell.
if ENV["RAILS_VERSION"] == "edge"
  gem "activesupport", github: "rails/rails", glob: "activesupport/*.gemspec"
elsif ENV["RAILS_VERSION"]
  gem "activesupport", "~> #{ENV["RAILS_VERSION"]}.0"
else
  gem "activesupport"
end

gem "rubocop", "~> 1.88"
gem "rubocop-minitest", "~> 0.39"

gem "rbs", "~> 4.0", require: false

gem "yard", "~> 0.9", require: false

gem "simplecov", "~> 0.22", require: false
gem "simplecov_json_formatter", "~> 0.1", require: false
