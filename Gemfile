# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in active_record_pretty_key.gemspec
gemspec

group :development, :test do
  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.0"
  gem "activerecord", "~> 8.1"
  gem "railties", "~> 8.1" # for the install generator spec
  gem "sqlite3", ">= 2.1"
end

# Database drivers for running the specs against other adapters (see README).
# Install with e.g. `BUNDLE_WITH=postgresql bundle install`.
group :postgresql, optional: true do
  gem "pg", "~> 1.5"
end

group :mysql, optional: true do
  gem "mysql2", "~> 0.5"
  gem "trilogy", "~> 2.9"
end

group :development do
  gem "pry", "~> 0.14"
end
