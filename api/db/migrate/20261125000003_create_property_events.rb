class CreatePropertyEvents < ActiveRecord::Migration[8.1]
  def change
    # Change log for price and status (Domain's Shortlist alerts). Written in
    # the same transaction as the change itself (Milestone 6), so history can never
    # miss one. Append-only: no updated_at.
    create_table :property_events do |t|
      t.references :property, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :from_value
      t.string :to_value
      t.datetime :created_at, null: false
    end

    add_check_constraint :property_events, "kind IN ('price_changed', 'status_changed')",
                         name: "property_events_kind_check"

    # Change history for a property, newest first.
    add_index :property_events, %i[property_id created_at], order: { created_at: :desc },
              name: "index_property_events_on_property_id_created_at"
  end
end
