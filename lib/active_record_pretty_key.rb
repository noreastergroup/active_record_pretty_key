# frozen_string_literal: true

require "active_record"
require "active_support/concern"
require "active_support/lazy_load_hooks"
require "sqids"
require_relative "active_record_pretty_key/version"
require_relative "active_record_pretty_key/concern"

module ActiveRecordPrettyKey
  class Error < StandardError; end
end

# PrettyKeyTicket subclasses ActiveRecord::Base. Defining it when the gem is
# required would load ActiveRecord::Base before the application's
# config.active_record settings are applied, so wait for ActiveRecord to load.
ActiveSupport.on_load(:active_record) do
  require_relative "active_record_pretty_key/pretty_key_ticket"
end
