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

  attribute :watched do |property|
    params.fetch(:watched) { property.has_attribute?(:watched) && property.watched }
  end
end
