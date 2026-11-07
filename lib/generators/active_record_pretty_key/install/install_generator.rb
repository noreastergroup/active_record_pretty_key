# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module ActiveRecordPrettyKey
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)
      desc "Creates the pretty_key_tickets table migration for active_record_pretty_key"

      def create_migration_file
        migration_template "create_pretty_key_tickets.rb.erb",
                           File.join(db_migrate_path, "create_pretty_key_tickets.rb")
      end

      private

      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
