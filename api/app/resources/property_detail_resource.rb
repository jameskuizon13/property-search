# GET /properties/:id: the list shape plus what only the property page shows,
# so a detail response can also refresh the cached card. Kept out of
# PropertyResource so search and live-update payloads stay small.
class PropertyDetailResource < PropertyResource
  attributes :description

  # Newest first. The caller passes the events in, already limited, so the
  # resource never runs an unbounded query. While the price is withheld, the
  # history leaves out every amount too: listing what it used to be would
  # undo the agent's choice to hide it.
  attribute :history do |property|
    PropertyEventResource.new(params.fetch(:history), params: { hide_prices: property.price_withheld? })
                         .serializable_hash
  end

  # False when older changes exist beyond the ones in `history`.
  attribute(:history_complete) { |_property| params.fetch(:history_complete) }

  # The whole gallery in order: the cover (image_url) first, then the rest.
  attribute :photos do |property|
    cover = property.image_url && { url: property.image_url, caption: "Main photo" }
    [ cover, *property.photos.map { |photo| { url: photo.url, caption: photo.caption } } ].compact
  end

  attribute(:agent) { |property| property.agent && AgentResource.new(property.agent).serializable_hash }

  # Upcoming open homes, soonest first, passed in already limited.
  attribute :inspections do |_property|
    InspectionResource.new(params.fetch(:inspections)).serializable_hash
  end

  # The listing's local time zone, e.g. "Australia/Perth", for open-home times.
  attribute(:time_zone) { |property| Property::TIME_ZONES.fetch(property.state) }
end
