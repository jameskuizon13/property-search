# One row per price or status change of a property (Domain's Shortlist
# alerts). Append-only, so there is no updated_at. Written in the same
# transaction as the change itself (Milestone 6).
class PropertyEvent < ApplicationRecord
  KINDS = %w[price_changed status_changed].freeze

  belongs_to :property

  enum :kind, KINDS.index_by(&:itself), validate: true
end
