# frozen_string_literal: true

module ActiveRecordPrettyKey
  class PrettyKeyTicket < ActiveRecord::Base
    self.table_name = "pretty_key_tickets"

    MIN_LENGTH = 4

    class << self
      # Generate a new unique integer ID.
      #
      # This runs inside the caller's transaction (e.g. a model's save), so it
      # must not hold locks longer than necessary:
      # - PostgreSQL: nextval() is non-transactional and takes no row locks.
      # - MySQL: UPDATE ... SET id = LAST_INSERT_ID(id + 1), the sequence
      #   emulation pattern from the MySQL manual. LAST_INSERT_ID() is scoped to
      #   the current connection. (Flickr's REPLACE INTO approach relies on
      #   MyISAM; on InnoDB concurrent REPLACEs deadlock.) The row lock is held
      #   until the caller's transaction commits, so concurrent creates queue.
      # - SQLite: REPLACE + last_insert_rowid(), also connection scoped.
      #   SQLite only allows a single writer, so there is no contention to avoid.
      #
      # Every query bypasses the Rails query cache: a cached
      # `SELECT nextval(...)` would hand out the same ID twice.
      def next_id
        adapter = connection.adapter_name.downcase

        id = uncached do
          case adapter
          when "postgresql", "postgis"
            connection.select_value("SELECT nextval(#{connection.quote(sequence_name)})")
          when "mysql", "mysql2", "trilogy"
            updated = connection.update("UPDATE #{quoted_table_name} SET id = LAST_INSERT_ID(id + 1) WHERE stub = 'a'")
            if updated.zero?
              raise ActiveRecordPrettyKey::Error,
                    "The #{table_name} table has no ticket row; run the active_record_pretty_key:install migration"
            end
            connection.select_value("SELECT LAST_INSERT_ID()")
          when "sqlite", "sqlite3"
            connection.execute("REPLACE INTO #{quoted_table_name} (stub) VALUES ('a')")
            connection.select_value("SELECT last_insert_rowid()")
          else
            raise ActiveRecordPrettyKey::Error,
                  "Unsupported database adapter #{connection.adapter_name.inspect}; " \
                  "supported adapters are PostgreSQL, PostGIS, MySQL (mysql2/trilogy) and SQLite"
          end
        end

        Integer(id)
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
    end
  end
end
