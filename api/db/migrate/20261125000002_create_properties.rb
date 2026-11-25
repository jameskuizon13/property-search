class CreateProperties < ActiveRecord::Migration[8.1]
  # Kept in step with Property::STATUSES, Property::PROPERTY_TYPES and
  # Property::STATES. Literal SQL on purpose: a migration must not change
  # meaning if the model's constants change later.
  ACTIVE = "status IN ('for_sale', 'under_offer')".freeze

  def change
    enable_extension "pg_trgm"

    create_table :properties do |t|
      t.string :street_address, null: false
      t.string :suburb, null: false
      t.string :state, null: false
      t.string :postcode, null: false
      t.decimal :latitude, precision: 9, scale: 6
      t.decimal :longitude, precision: 9, scale: 6

      # Many Australian listings hide the price: filters and sorts use the
      # number (NULL when withheld), the card shows the display string.
      t.bigint :price_cents
      t.string :price_display, null: false

      t.integer :bedrooms, limit: 2, null: false, default: 0
      t.integer :bathrooms, limit: 2, null: false, default: 0
      t.integer :car_spaces, limit: 2, null: false, default: 0
      t.integer :land_size_sqm

      t.string :property_type, null: false
      t.string :status, null: false, default: "for_sale"
      t.datetime :listed_at, null: false
      t.string :image_url
      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end

    add_check_constraint :properties, "state IN ('NSW', 'VIC', 'QLD', 'WA', 'SA', 'TAS', 'ACT', 'NT')",
                         name: "properties_state_check"
    add_check_constraint :properties, "postcode ~ '^[0-9]{4}$'", name: "properties_postcode_check"
    add_check_constraint :properties, "status IN ('for_sale', 'under_offer', 'sold', 'withdrawn')",
                         name: "properties_status_check"
    add_check_constraint :properties,
                         "property_type IN ('house', 'apartment_unit', 'townhouse', 'villa', 'land', 'acreage', " \
                         "'rural', 'block_of_units', 'retirement_living')",
                         name: "properties_property_type_check"
    add_check_constraint :properties, "price_cents IS NULL OR price_cents >= 0", name: "properties_price_cents_check"
    add_check_constraint :properties, "bedrooms >= 0 AND bathrooms >= 0 AND car_spaces >= 0",
                         name: "properties_rooms_check"
    add_check_constraint :properties, "land_size_sqm IS NULL OR land_size_sqm >= 0",
                         name: "properties_land_size_check"
    add_check_constraint :properties, "latitude IS NULL OR latitude BETWEEN -90 AND 90",
                         name: "properties_latitude_check"
    add_check_constraint :properties, "longitude IS NULL OR longitude BETWEEN -180 AND 180",
                         name: "properties_longitude_check"

    # Default "newest" feed: walk the index in order, stop after limit + 1.
    # Partial on the exact SQL Property.active produces.
    add_index :properties, %i[listed_at id], order: { listed_at: :desc, id: :desc },
              where: ACTIVE, name: "index_properties_active_on_listed_at_id"

    # Price low→high, and high→low by scanning backwards. Price sorts leave
    # out withheld prices, hence IS NOT NULL.
    add_index :properties, %i[price_cents id],
              where: "#{ACTIVE} AND price_cents IS NOT NULL", name: "index_properties_active_on_price_cents_id"

    # Narrow searches ("villas, 4+ beds"): find the few matches, then sort.
    add_index :properties, %i[property_type bedrooms],
              where: ACTIVE, name: "index_properties_active_on_property_type_bedrooms"

    # Free text q: suburb ILIKE '%q%' OR street_address ILIKE '%q%' OR postcode LIKE 'q%'.
    add_index :properties, :suburb, using: :gin, opclass: :gin_trgm_ops, name: "index_properties_on_suburb_trgm"
    add_index :properties, :street_address, using: :gin, opclass: :gin_trgm_ops,
              name: "index_properties_on_street_address_trgm"
    add_index :properties, :postcode, opclass: :text_pattern_ops, name: "index_properties_on_postcode_pattern"
  end
end
