# A gallery photo after the property's cover (Property#image_url).
class PropertyPhoto < ApplicationRecord
  belongs_to :property

  # Our own static photos only: an outside host would see every visitor's IP.
  # Uploads (planned with the admin screens) will need their own rule.
  validates :url, format: { with: Property::PHOTO_PATH }, length: { maximum: 500 }
  validates :caption, presence: true, length: { maximum: 100 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 1 },
                       uniqueness: { scope: :property_id }
end
