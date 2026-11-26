# One open-home time for a property.
class Inspection < ApplicationRecord
  belongs_to :property

  # Not over yet: an inspection that has started still shows until it ends.
  scope :upcoming, ->(now = Time.current) { where(ends_at: now..).order(:starts_at, :id) }

  validates :starts_at, :ends_at, presence: true
  validate :ends_after_start

  private

  def ends_after_start
    errors.add(:ends_at, "must be after the start") if starts_at && ends_at && ends_at <= starts_at
  end
end
