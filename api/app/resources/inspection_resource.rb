# One open home. Times are UTC; the page shows them in the listing's own time
# zone (`timeZone` on the property), not the viewer's.
class InspectionResource
  include Alba::Resource

  transform_keys :lower_camel

  attributes :id, :starts_at, :ends_at
end
