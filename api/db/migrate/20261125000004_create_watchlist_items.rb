class CreateWatchlistItems < ActiveRecord::Migration[8.1]
  def change
    # Created in Batch 3 because search computes `watched` with a LEFT JOIN on
    # this table; the watchlist endpoints come in Batch 4.
    create_table :watchlist_items do |t|
      # The unique (user_id, property_id) index below leads with user_id, so
      # it also serves "this user's items"; no separate user_id index.
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      # Finding the watchers of a property when it changes (Batch 6).
      t.references :property, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :created_at, null: false
    end

    add_index :watchlist_items, %i[user_id property_id], unique: true
  end
end
