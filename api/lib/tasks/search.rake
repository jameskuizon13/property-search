namespace :search do
  desc "Print EXPLAIN ANALYZE for the main search shapes (seed with SEED_COUNT=100000 first)"
  task explain: :environment do
    connection = ActiveRecord::Base.connection
    connection.execute("ANALYZE properties")
    demo = User.find_by(email: "demo@example.com")
    first_page = Properties::SearchQuery.new({}).call

    {
      "Newest#{' (signed in, watched LEFT JOIN)' if demo}" => [ {}, demo ],
      "Newest, second batch (cursor)" => [ { "cursor" => first_page.meta[:next_cursor] }, nil ],
      "Price low to high" => [ { "sort" => "price_asc" }, nil ],
      "Price high to low" => [ { "sort" => "price_desc" }, nil ],
      "Narrow: villas, 4+ beds" => [ { "propertyTypes" => [ "villa" ], "minBedrooms" => "4" }, nil ],
      "Narrow: acreage, 5+ beds" => [ { "propertyTypes" => [ "acreage" ], "minBedrooms" => "5" }, nil ],
      "Free text q=fitz (common)" => [ { "q" => "fitz" }, nil ],
      "Free text q=jetty (rare)" => [ { "q" => "jetty" }, nil ],
      "Free text q=30 (postcode prefix)" => [ { "q" => "30" }, nil ]
    }.each do |label, (params, user)|
      # The exact SQL Rails sends for that page, run once to warm the cache.
      sql = Properties::SearchQuery.new(params, user:).relation.to_sql
      connection.select_all(sql)
      puts "### #{label}", connection.select_rows("EXPLAIN (ANALYZE) #{sql}").map(&:first), ""
    end
  end
end
