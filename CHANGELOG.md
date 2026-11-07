# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-11-07

### Fixed
- Custom Sqids alphabet from Rails credentials is now read lazily on first use; previously it was read when the gem loaded (before `Rails.application` exists) and silently ignored
- PostgreSQL ticket generation uses `nextval()` and no longer holds a row lock on the tickets table for the duration of the caller's transaction
- MySQL via the Trilogy adapter is now supported; previously it fell through to a fallback that could hand out duplicate IDs under concurrency
- SQLite ticket generation uses the connection-scoped `last_insert_rowid()` instead of reading the last row
- `generate_pretty_key` is now public, as documented, and returns the record's key
- MySQL ticket generation no longer deadlocks under concurrency: concurrent `REPLACE INTO` statements deadlock on InnoDB, so it now uses `UPDATE ... SET id = LAST_INSERT_ID(id + 1)`
- Requiring the gem no longer loads `ActiveRecord::Base` early (before the app's ActiveRecord configuration is applied)
- `ActiveRecordPrettyKey::VERSION` is now defined when the gem is required
- Install generator uses Rails' migration numbering and refuses to create a duplicate migration; the generated migration can be rolled back

### Changed
- Unsupported database adapters now raise `ActiveRecordPrettyKey::Error` instead of using an unsafe fallback
- README: corrected security claims and documented that the alphabet must not change once records exist
- Requires Ruby 3.0+ (as the `sqids` dependency always has) and ActiveRecord 6.1 – 8.x
- Gem releases require RubyGems MFA; README, LICENSE and CHANGELOG are now packaged
- Development: specs run against SQLite, PostgreSQL, MySQL (mysql2 and Trilogy) in CI; added `bin/console`; fixed `bin/setup` and `bin/build`

### Removed
- Broken `Thorfile` and `bin/active_record_pretty_key` executable (neither could load the generator), and the `thor` dependency

## [0.1.1] - 2025-08-25

### Fixed
- Fixed Gemspec homepage

## [0.1.0] - 2025-08-25

### Added
- Initial gem structure
- Basic concern `ActiveRecordPrettyKey::Concern` module for ActiveRecord models
- `generate_pretty_key` instance method
- RSpec test suite
- Development tools and scripts
