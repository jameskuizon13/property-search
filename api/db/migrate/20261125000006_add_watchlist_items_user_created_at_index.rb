class AddWatchlistItemsUserCreatedAtIndex < ActiveRecord::Migration[8.1]
  # GET /watchlist lists one user's items newest first and pages with a
  # keyset cursor on (created_at, id). This index serves both the order and
  # the `(created_at, id) < (?, ?)` condition, so a page reads only its own
  # rows instead of sorting the whole watchlist. The unique
  # (user_id, property_id) index stays: it enforces one row per property.
  def change
    add_index :watchlist_items, %i[user_id created_at id], order: { created_at: :desc, id: :desc },
                                                           name: "index_watchlist_items_on_user_id_created_at_id"
  end
end
