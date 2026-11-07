require "bundler/setup"
require "active_record_pretty_key"
require "active_record"

# Pick the database with DB=sqlite3|postgresql|mysql2|trilogy (default sqlite3).
# DATABASE_URL overrides the connection settings for the selected adapter.
TEST_DB = ENV.fetch("DB", "sqlite3")

DB_CONFIGS = {
  "sqlite3" => { adapter: "sqlite3", database: ":memory:" },
  "postgresql" => {
    adapter: "postgresql", host: "127.0.0.1", port: 5432,
    username: "postgres", password: "postgres", database: "pretty_key_test"
  },
  "mysql2" => {
    adapter: "mysql2", host: "127.0.0.1", port: 3306,
    username: "root", password: "root", database: "pretty_key_test"
  },
  "trilogy" => {
    adapter: "trilogy", host: "127.0.0.1", port: 3306,
    username: "root", password: "root", database: "pretty_key_test"
  }
}.freeze

db_config = DB_CONFIGS.fetch(TEST_DB) { abort "Unknown DB=#{TEST_DB}; expected one of #{DB_CONFIGS.keys.join(', ')}" }
# CI sets an empty DATABASE_URL for SQLite; ActiveRecord itself rejects that
ENV.delete("DATABASE_URL") if ENV["DATABASE_URL"].to_s.strip.empty?
db_config = db_config.merge(url: ENV["DATABASE_URL"]) if ENV["DATABASE_URL"]
ActiveRecord::Base.establish_connection(db_config.merge(pool: 10))

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Clean up database between tests
  config.before(:each) do
    ActiveRecord::Base.connection.tables.each do |table|
      ActiveRecord::Base.connection.drop_table(table, force: :cascade)
    end
  end

  # Create the pretty_key_tickets table exactly as the install generator does
  config.before(:each) do
    connection = ActiveRecord::Base.connection
    connection.create_table :pretty_key_tickets, id: :bigint do |t|
      t.string :stub, limit: 1, null: false
    end
    connection.add_index :pretty_key_tickets, :stub, unique: true
    connection.execute "INSERT INTO pretty_key_tickets (stub) VALUES ('a')"
  end

  # The Sqids encoder is memoized; reset it so per-test alphabets take effect
  config.before(:each) do
    ActiveRecordPrettyKey::PrettyKeyTicket.instance_variable_set(:@sqids, nil)
  end

  # Skip examples that only make sense for some adapters, e.g. `adapters: %w[postgresql]`
  config.before(:each) do |example|
    adapters = example.metadata[:adapters]
    skip "not applicable to #{TEST_DB}" if adapters && !adapters.include?(TEST_DB)
  end
end
