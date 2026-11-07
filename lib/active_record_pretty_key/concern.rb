# frozen_string_literal: true

module ActiveRecordPrettyKey
  module Concern
    extend ActiveSupport::Concern

    included do
      before_create :generate_pretty_key
    end

    # Assigns a pretty key to the primary key if it is a string column and
    # not already set. Returns the primary key value, or nil when the model's
    # primary key is not a single string column.
    def generate_pretty_key
      pk = self.class.primary_key
      return unless pk.is_a?(String) && self.class.type_for_attribute(pk).type == :string

      self[pk] = ActiveRecordPrettyKey::PrettyKeyTicket.next_sqid if self[pk].blank?
      self[pk]
    end
  end
end
