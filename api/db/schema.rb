# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_26_000004) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "agents", force: :cascade do |t|
    t.string "name", null: false
    t.string "agency", null: false
    t.string "phone", null: false
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "inspections", force: :cascade do |t|
    t.bigint "property_id", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["property_id", "starts_at"], name: "index_inspections_on_property_id_and_starts_at"
    t.check_constraint "ends_at > starts_at", name: "inspections_ends_after_start"
  end

  create_table "properties", force: :cascade do |t|
    t.string "street_address", null: false
    t.string "suburb", null: false
    t.string "state", null: false
    t.string "postcode", null: false
    t.decimal "latitude", precision: 9, scale: 6
    t.decimal "longitude", precision: 9, scale: 6
    t.bigint "price_cents"
    t.string "price_display", null: false
    t.integer "bedrooms", limit: 2, default: 0, null: false
    t.integer "bathrooms", limit: 2, default: 0, null: false
    t.integer "car_spaces", limit: 2, default: 0, null: false
    t.integer "land_size_sqm"
    t.string "property_type", null: false
    t.string "status", default: "for_sale", null: false
    t.datetime "listed_at", null: false
    t.string "image_url"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.bigint "agent_id"
    t.index ["agent_id"], name: "index_properties_on_agent_id"
    t.index ["listed_at", "id"], name: "index_properties_active_on_listed_at_id", order: :desc, where: "((status)::text = ANY ((ARRAY['for_sale'::character varying, 'under_offer'::character varying])::text[]))"
    t.index ["postcode"], name: "index_properties_on_postcode_pattern", opclass: :text_pattern_ops
    t.index ["price_cents", "id"], name: "index_properties_active_on_price_cents_id", where: "(((status)::text = ANY ((ARRAY['for_sale'::character varying, 'under_offer'::character varying])::text[])) AND (price_cents IS NOT NULL))"
    t.index ["property_type", "bedrooms"], name: "index_properties_active_on_property_type_bedrooms", where: "((status)::text = ANY ((ARRAY['for_sale'::character varying, 'under_offer'::character varying])::text[]))"
    t.index ["street_address"], name: "index_properties_on_street_address_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["suburb"], name: "index_properties_on_suburb_trgm", opclass: :gin_trgm_ops, using: :gin
    t.check_constraint "bedrooms >= 0 AND bathrooms >= 0 AND car_spaces >= 0", name: "properties_rooms_check"
    t.check_constraint "land_size_sqm IS NULL OR land_size_sqm >= 0", name: "properties_land_size_check"
    t.check_constraint "latitude IS NULL OR latitude >= '-90'::integer::numeric AND latitude <= 90::numeric", name: "properties_latitude_check"
    t.check_constraint "longitude IS NULL OR longitude >= '-180'::integer::numeric AND longitude <= 180::numeric", name: "properties_longitude_check"
    t.check_constraint "postcode::text ~ '^[0-9]{4}$'::text", name: "properties_postcode_check"
    t.check_constraint "price_cents IS NULL OR price_cents >= 0", name: "properties_price_cents_check"
    t.check_constraint "property_type::text = ANY (ARRAY['house'::character varying, 'apartment_unit'::character varying, 'townhouse'::character varying, 'villa'::character varying, 'land'::character varying, 'acreage'::character varying, 'rural'::character varying, 'block_of_units'::character varying, 'retirement_living'::character varying]::text[])", name: "properties_property_type_check"
    t.check_constraint "state::text = ANY (ARRAY['NSW'::character varying, 'VIC'::character varying, 'QLD'::character varying, 'WA'::character varying, 'SA'::character varying, 'TAS'::character varying, 'ACT'::character varying, 'NT'::character varying]::text[])", name: "properties_state_check"
    t.check_constraint "status::text = ANY (ARRAY['for_sale'::character varying, 'under_offer'::character varying, 'sold'::character varying, 'withdrawn'::character varying]::text[])", name: "properties_status_check"
  end

  create_table "property_events", force: :cascade do |t|
    t.bigint "property_id", null: false
    t.string "kind", null: false
    t.string "from_value"
    t.string "to_value"
    t.datetime "created_at", null: false
    t.index ["property_id", "created_at"], name: "index_property_events_on_property_id_created_at", order: { created_at: :desc }
    t.check_constraint "kind::text = ANY (ARRAY['price_changed'::character varying, 'status_changed'::character varying]::text[])", name: "property_events_kind_check"
  end

  create_table "property_photos", force: :cascade do |t|
    t.bigint "property_id", null: false
    t.string "url", null: false
    t.string "caption", null: false
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["property_id", "position"], name: "index_property_photos_on_property_id_and_position", unique: true
    t.check_constraint "\"position\" >= 1", name: "property_photos_position_positive"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "role", default: "user", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.check_constraint "role::text = ANY (ARRAY['user'::character varying, 'admin'::character varying]::text[])", name: "users_role_check"
  end

  create_table "watchlist_items", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "property_id", null: false
    t.datetime "created_at", null: false
    t.index ["property_id"], name: "index_watchlist_items_on_property_id"
    t.index ["user_id", "created_at", "id"], name: "index_watchlist_items_on_user_id_created_at_id", order: { created_at: :desc, id: :desc }
    t.index ["user_id", "property_id"], name: "index_watchlist_items_on_user_id_and_property_id", unique: true
  end

  add_foreign_key "inspections", "properties", on_delete: :cascade
  add_foreign_key "properties", "agents", on_delete: :nullify
  add_foreign_key "property_events", "properties", on_delete: :cascade
  add_foreign_key "property_photos", "properties", on_delete: :cascade
  add_foreign_key "watchlist_items", "properties", on_delete: :cascade
  add_foreign_key "watchlist_items", "users", on_delete: :cascade
end
