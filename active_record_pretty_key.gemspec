# frozen_string_literal: true

require_relative "lib/active_record_pretty_key/version"

Gem::Specification.new do |spec|
  spec.name = "active_record_pretty_key"
  spec.version = ActiveRecordPrettyKey::VERSION
  spec.authors = ["Stuart Yamartino", "John Nagro"]
  spec.email = ["stu@stuyam.com", "john.nagro@gmail.com"]

  spec.summary = "A gem for generating pretty keys in ActiveRecord models"
  spec.description = "ActiveRecordPrettyKey provides functionality to generate and manage pretty, human-readable keys for ActiveRecord models."
  spec.homepage = "https://github.com/noreastergroup/active_record_pretty_key"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0" # sqids requires Ruby 3.0+

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*"] + %w[VERSION README.md LICENSE CHANGELOG.md]
  spec.require_paths = ["lib"]

  # 6.1 is the oldest Rails release that supports Ruby 3.0
  spec.add_dependency "activerecord", ">= 6.1", "< 9"
  spec.add_dependency "activesupport", ">= 6.1", "< 9"
  spec.add_dependency "sqids", "~> 0.1"
end
