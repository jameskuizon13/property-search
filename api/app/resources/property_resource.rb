# The property shape shared by search, the watchlist and live updates, so the
# client can drop a broadcast straight into its cache.
#
# `watched` comes from the search query's LEFT JOIN (a selected column). A
# Property loaded elsewhere doesn't have it, so callers that know the answer
# pass it in: PropertyResource.new(property, params: { watched: true }).
class PropertyResource
  include Alba::Resource

  transform_keys :lower_camel

  attributes :id, :street_address, :suburb, :state, :postcode,
             :price_cents, :price_display, :bedrooms, :bathrooms, :car_spaces, :land_size_sqm,
             :property_type, :status, :listed_at, :image_url

  # decimal columns would serialise as strings
  attribute(:latitude) { |property| property.latitude&.to_f }
  attribute(:longitude) { |property| property.longitude&.to_f }

  # lock_version, which Rails bumps on every save. Live updates carry it too,
  # and the client applies one only if it is newer than the card it has, so a
  # late or repeated message can never put an older price back.
  attribute(:version, &:lock_version)

  attribute :watched do |property|
    params.fetch(:watched) { property.has_attribute?(:watched) && property.watched }
  end
end
