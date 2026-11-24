# A user watching a property. Append-or-delete only, so there is no
# updated_at. Both FKs cascade in the database.
class WatchlistItem < ApplicationRecord
  belongs_to :user
  belongs_to :property
end
