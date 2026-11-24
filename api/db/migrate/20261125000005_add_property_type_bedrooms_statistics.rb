class AddPropertyTypeBedroomsStatistics < ActiveRecord::Migration[8.1]
  # Postgres assumes columns are independent, so for "villas with 4+ beds" it
  # multiplies two selectivities and expects ~1,200 matches when there are
  # none. It then walks the newest-first index hoping to fill the page early
  # and reads every active row (~33 ms at 100k). MCV statistics over the pair
  # tell it the combination is rare, so it uses the (property_type, bedrooms)
  # index instead (~0.03 ms). See the README's EXPLAIN section.
  #
  # schema.rb can't express CREATE STATISTICS, so db/seeds.rb also creates
  # it (IF NOT EXISTS) for databases built from schema.rb.
  def up
    execute "CREATE STATISTICS IF NOT EXISTS properties_type_bedrooms_stats (mcv) ON property_type, bedrooms FROM properties"
  end

  def down
    execute "DROP STATISTICS IF EXISTS properties_type_bedrooms_stats"
  end
end
