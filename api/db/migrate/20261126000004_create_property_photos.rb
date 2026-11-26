# A listing's gallery after its main photo (properties.image_url stays the
# cover, so search never needs this table).
class CreatePropertyPhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :property_photos do |t|
      t.references :property, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :url, null: false
      # Read out by screen readers ("Kitchen"), since the photos aren't of the real home.
      t.string :caption, null: false
      t.integer :position, null: false
      t.timestamps
    end

    add_check_constraint :property_photos, "position >= 1", name: "property_photos_position_positive"
    # The gallery in order, and no two photos in one place.
    add_index :property_photos, %i[property_id position], unique: true
  end
end
