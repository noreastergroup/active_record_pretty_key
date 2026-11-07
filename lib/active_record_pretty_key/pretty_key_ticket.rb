# frozen_string_literal: true

require "concurrent/map"
require "concurrent/atomic/atomic_fixnum"

module ActiveRecordPrettyKey
  class PrettyKeyTicket < ActiveRecord::Base
    self.table_name = "pretty_key_tickets"

    MIN_LENGTH = 4
    MYSQL_DEADLOCK_ATTEMPTS = 5

    @ticket_connection_pools = Concurrent::Map.new
    @ticket_connection_count = Concurrent::AtomicFixnum.new

    class << self
      # Generate a new unique integer ID.
      #
      # This is usually called inside the caller's transaction (a model's
      # save). An issued ID must never be handed out again, even if that
      # transaction rolls back, and allocation must not hold locks until the
      # caller commits:
      # - PostgreSQL: nextval() is non-transactional and takes no row locks.
      # - MySQL: UPDATE ... SET id = LAST_INSERT_ID(id + 1), the sequence
      #   emulation pattern from the MySQL manual. (Flickr's REPLACE INTO relies
      #   on MyISAM; on InnoDB concurrent REPLACEs deadlock.) An UPDATE is
      #   transactional, so it runs on a dedicated autocommit connection: it
      #   commits immediately and its row lock is released straight away.
      # - SQLite: REPLACE + last_insert_rowid(). SQLite allows a single writer,
      #   so a second connection would deadlock with the caller's transaction;
      #   the ticket is rolled back along with the caller's transaction.
      #
      # Every query bypasses the Rails query cache: a cached
      # `SELECT nextval(...)` would hand out the same ID twice.
      #
      # Connections are borrowed with connection_pool.with_connection, which
      # reuses the thread's current connection (and so its transaction).
      # Calling `connection` instead would, on Rails 7.2+, keep the connection
      # checked out by the thread after the caller is done with it.
      def next_id
        id = connection_pool.with_connection do |conn|
          case conn.adapter_name.downcase
          when "postgresql", "postgis"
            conn.uncached { conn.select_value("SELECT nextval(#{conn.quote(sequence_name)})") }
          when "mysql", "mysql2", "trilogy"
            ticket_connection_pool.with_connection { |ticket_conn| ticket_conn.uncached { mysql_next_id(ticket_conn) } }
          when "sqlite", "sqlite3"
            conn.uncached do
              conn.execute("REPLACE INTO #{quoted_table_name} (stub) VALUES ('a')")
              conn.select_value("SELECT last_insert_rowid()")
            end
          else
            raise ActiveRecordPrettyKey::Error,
                  "Unsupported database adapter #{conn.adapter_name.inspect}; " \
                  "supported adapters are PostgreSQL, PostGIS, MySQL (mysql2/trilogy) and SQLite"
          end
        end

        Integer(id)
      end

      # Connection pool used only for MySQL ticket allocation, separate from
      # the application's pool so allocations commit independently of the
      # caller's transaction. One pool per database config (so multiple
      # databases and shards each get their own), created on first use with
      # the same settings, including pool size, as the application's pool.
      # Registered through establish_connection so Rails manages it (e.g.
      # discarding it after fork); the pool object is used directly so it
      # works regardless of the caller's connected_to role or shard.
      def ticket_connection_pool
        db_config = connection_db_config
        @ticket_connection_pools.compute_if_absent(db_config.configuration_hash) do
          # establish_connection needs a named class to own the pool
          owner = Class.new(ActiveRecord::Base) { self.abstract_class = true }
          ActiveRecordPrettyKey.const_set("TicketConnection#{@ticket_connection_count.increment}", owner)
          owner.establish_connection(db_config)
        end
      end

      def next_sqid
        sqids.encode([ next_id ])
      end

      # Built lazily so Rails credentials are available. The gem is loaded by
      # Bundler.require before Rails.application exists, so reading credentials
      # at class-load time would silently fall back to the default alphabet.
      def sqids
        @sqids ||= Sqids.new(min_length: MIN_LENGTH, alphabet: alphabet)
      end

      def alphabet
        configured =
          if defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application
            ::Rails.application.credentials.dig(:sqids, :alphabet)
          end

        configured.presence || Sqids::DEFAULT_ALPHABET
      end

      private

      def mysql_next_id(conn)
        attempts = 0
        begin
          attempts += 1
          mysql_allocate(conn)
        rescue ActiveRecord::Deadlocked
          # Each statement runs in its own autocommit transaction, so the
          # deadlock victim issued nothing and can safely be retried. (Not if
          # something, e.g. a test harness, opened a transaction around it.)
          retry if attempts < MYSQL_DEADLOCK_ATTEMPTS && !conn.transaction_open?
          raise
        end
      end

      def mysql_allocate(conn)
        update = "UPDATE #{quoted_table_name} SET id = LAST_INSERT_ID(id + 1) WHERE stub = 'a'"

        if conn.update(update).zero?
          # The row seeded by the install migration is missing, e.g. in a
          # database built from schema.rb (db:schema:load, db:prepare, test
          # databases). Create it; IGNORE covers a concurrent insert. MySQL 8
          # moves the AUTO_INCREMENT counter past values set by UPDATE, so the
          # new row can't start below IDs that were already issued. Concurrent
          # INSERT IGNORE and UPDATE can deadlock here; the caller retries.
          conn.execute("INSERT IGNORE INTO #{quoted_table_name} (stub) VALUES ('a')")

          if conn.update(update).zero?
            raise ActiveRecordPrettyKey::Error, "Could not create the ticket row in #{table_name}"
          end
        end

        conn.select_value("SELECT LAST_INSERT_ID()")
      end
    end
  end
end
