require "rails_helper"

RSpec.describe "GET /api/v1/properties", type: :request do
  def search(params = {})
    get "/api/v1/properties", params:, headers: json_headers
  end

  def ids = json[:data].pluck(:id)

  # Follows nextCursor until hasMore is false; returns every id in order.
  def walk(params)
    params = params.dup
    seen = []
    cursor = params.delete(:cursor)
    loop do
      search(params.merge(cursor:).compact)
      expect(response).to have_http_status(:ok)
      seen.concat(ids)
      break unless json[:meta][:hasMore]

      cursor = json[:meta][:nextCursor]
      expect(cursor).to be_present
    end
    seen
  end

  describe "response shape" do
    it "returns camelCase properties and paging meta, without signing in" do
      property = create(:property, listed_at: Time.zone.parse("2026-11-01 00:00:00"))
      search

      expect(response).to have_http_status(:ok)
      expect(json[:data].first).to eq(
        id: property.id, streetAddress: property.street_address, suburb: "Fitzroy", state: "VIC",
        postcode: "3065", latitude: -37.798, longitude: 144.978, priceCents: 85_000_000,
        priceDisplay: "$850,000", bedrooms: 3, bathrooms: 2, carSpaces: 1, landSizeSqm: 320,
        propertyType: "house", status: "for_sale", listedAt: "2026-11-01T00:00:00.000Z",
        imageUrl: nil, version: 0, watched: false
      )
      expect(json[:meta]).to eq(limit: 20, hasMore: false, totalCount: 1)
    end

    it "exposes lock_version only as version, and no timestamps" do
      property = create(:property)
      property.update!(bedrooms: 4)
      search
      expect(json[:data].first[:version]).to eq(1)
      expect(json[:data].first.keys).not_to include(:lockVersion, :createdAt, :updatedAt)
    end
  end

  describe "status" do
    let!(:for_sale) { create(:property, status: "for_sale") }
    let!(:under_offer) { create(:property, status: "under_offer") }

    before do
      create(:property, status: "sold")
      create(:property, status: "withdrawn")
    end

    it "returns for sale and under offer, never sold or withdrawn" do
      search
      expect(ids).to contain_exactly(for_sale.id, under_offer.id)
      expect(json[:meta][:totalCount]).to eq(2)
    end

    it "narrows to for sale with excludeUnderOffer" do
      search(excludeUnderOffer: "true")
      expect(ids).to eq([ for_sale.id ])
    end

    it "ignores a status param (there is none)" do
      search(status: "sold")
      expect(ids).to contain_exactly(for_sale.id, under_offer.id)
    end
  end

  describe "filters" do
    let!(:cheap_unit) do
      create(:property, property_type: "apartment_unit", bedrooms: 1, price_cents: 40_000_000,
                        price_display: "$400,000", suburb: "Fitzroy", postcode: "3065")
    end
    let!(:family_house) do
      create(:property, property_type: "house", bedrooms: 4, price_cents: 120_000_000,
                        price_display: "$1,200,000", suburb: "Richmond", postcode: "3121")
    end
    let!(:withheld_villa) do
      create(:property, :price_withheld, property_type: "villa", bedrooms: 3,
                                         suburb: "Glenelg", state: "SA", postcode: "5045",
                                         street_address: "9 Jetty Rd")
    end

    it "filters by minimum price, leaving out withheld prices" do
      search(minPrice: "500000")
      expect(ids).to eq([ family_house.id ])
    end

    it "filters by maximum price" do
      search(maxPrice: "500000")
      expect(ids).to eq([ cheap_unit.id ])
    end

    it "treats min and max price as inclusive" do
      search(minPrice: "400000", maxPrice: "400000")
      expect(ids).to eq([ cheap_unit.id ])
    end

    it "filters by minimum bedrooms (a minimum, not an exact count)" do
      search(minBedrooms: "3")
      expect(ids).to contain_exactly(family_house.id, withheld_villa.id)
    end

    it "filters by one or more property types" do
      search(propertyTypes: [ "villa" ])
      expect(ids).to eq([ withheld_villa.id ])

      search(propertyTypes: %w[villa apartment_unit])
      expect(ids).to contain_exactly(withheld_villa.id, cheap_unit.id)
    end

    it "accepts property types as a comma-separated list too" do
      search(propertyTypes: "villa,apartment_unit")
      expect(ids).to contain_exactly(withheld_villa.id, cheap_unit.id)
    end

    it "hides withheld prices with excludePriceWithheld" do
      search(excludePriceWithheld: "1")
      expect(ids).to contain_exactly(cheap_unit.id, family_house.id)
    end

    it "combines filters, and counts only the matching rows" do
      search(minBedrooms: "1", maxPrice: "1500000", propertyTypes: %w[house apartment_unit], q: "rich")
      expect(ids).to eq([ family_house.id ])
      expect(json[:meta][:totalCount]).to eq(1)
    end

    describe "free text q" do
      it "matches suburb, case-insensitive and partial" do
        search(q: "FITZ")
        expect(ids).to eq([ cheap_unit.id ])
      end

      it "matches the street address" do
        search(q: "jetty")
        expect(ids).to eq([ withheld_villa.id ])
      end

      it "matches the start of a postcode only" do
        search(q: "31")
        expect(ids).to eq([ family_house.id ])

        search(q: "21") # inside 3121, but not its start
        expect(ids).to be_empty
      end

      it "ignores q shorter than 2 characters after trimming" do
        search(q: " f ")
        expect(ids.size).to eq(3)
      end

      it "treats % and _ literally" do
        search(q: "%%")
        expect(ids).to be_empty
      end
    end
  end

  describe "sorting" do
    let!(:old_cheap) { create(:property, listed_at: 3.days.ago, price_cents: 50_000_000) }
    let!(:new_dear) { create(:property, listed_at: 1.day.ago, price_cents: 90_000_000) }
    let!(:mid_withheld) { create(:property, :price_withheld, listed_at: 2.days.ago) }

    it "defaults to newest first" do
      search
      expect(ids).to eq([ new_dear.id, mid_withheld.id, old_cheap.id ])
    end

    it "sorts by price low to high, leaving out withheld prices" do
      search(sort: "price_asc")
      expect(ids).to eq([ old_cheap.id, new_dear.id ])
      expect(json[:meta][:totalCount]).to eq(2)
    end

    it "sorts by price high to low, leaving out withheld prices" do
      search(sort: "price_desc")
      expect(ids).to eq([ new_dear.id, old_cheap.id ])
    end
  end

  describe "keyset pagination" do
    def microseconds(n) = Rational(n, 1_000_000) # exact, unlike float seconds

    # Ties on purpose: shared listed_at values, shared prices, and listed_at
    # values only microseconds apart (the same millisecond in JSON). The
    # later-microsecond rows are created first, so they get the lower ids.
    before do
      base = Time.zone.parse("2026-11-20 10:00:00.123456")
      times = [ base + microseconds(300), base + microseconds(1), base, base, base - microseconds(400),
                base - 1, base - 1, base - 2 ]
      prices = [ 50, 50, 50, 60, 60, 70, nil, 80 ].map { |dollars_k| dollars_k && dollars_k * 1_000_000 }
      25.times do |i|
        price = prices[i % prices.size]
        create(:property, listed_at: times[i % times.size] - (i / times.size).days,
                          price_cents: price, price_display: price ? "$#{price / 100}" : "Contact agent")
      end
    end

    %w[newest price_asc price_desc].each do |sort|
      it "visits every row exactly once in #{sort} order" do
        # Expected order computed in Ruby, independently of the query code.
        rows = Property.all.to_a
        rows = rows.select(&:price_cents) unless sort == "newest"
        expected = case sort
        when "newest" then rows.sort_by { |p| [ -p.listed_at.to_r, -p.id ] }
        when "price_asc" then rows.sort_by { |p| [ p.price_cents, p.id ] }
        when "price_desc" then rows.sort_by { |p| [ -p.price_cents, -p.id ] }
        end.map(&:id)

        seen = walk(sort:, limit: "4")

        expect(seen).to eq(expected)
        expect(seen.uniq.size).to eq(seen.size)
        expect(seen.size).to eq(sort == "newest" ? 25 : 22) # 3 withheld prices left out
      end
    end

    it "keeps microseconds in the cursor, so rows sharing a millisecond are never skipped" do
      Property.delete_all
      base = Time.zone.parse("2026-11-21 08:00:00.500000")
      # Same millisecond, newest first by microsecond; the newest has the lowest id.
      [ 900, 400, 100 ].each { |us| create(:property, listed_at: base + microseconds(us)) }

      expect(walk(limit: "1").size).to eq(3)

      # Mutation check: the same walk with a millisecond cursor (the bug the
      # microsecond cursor exists to prevent) loses the other two rows.
      allow(Properties::Cursor).to receive(:microseconds).and_wrap_original { |original, time| original.call(time) / 1_000 * 1_000 }
      expect(walk(limit: "1").size).to eq(1)
    end

    it "keeps the walk stable when a newer listing arrives mid-walk" do
      search(limit: "5")
      first_page = ids
      create(:property, listed_at: 1.minute.from_now)

      rest = walk(limit: "5", cursor: json[:meta][:nextCursor])
      expect((first_page + rest).size).to eq(25)
      expect((first_page + rest).uniq.size).to eq(25)
    end

    it "reports hasMore and nextCursor only while rows remain, and totalCount only on the first batch" do
      search(limit: "20")
      expect(json[:meta]).to include(hasMore: true, totalCount: 25, limit: 20)

      search(limit: "20", cursor: json[:meta][:nextCursor])
      expect(ids.size).to eq(5)
      expect(json[:meta]).to eq(limit: 20, hasMore: false)
    end

    it "returns 20 rows by default" do
      search
      expect(ids.size).to eq(20)
    end

    it "uses a URL-safe cursor" do
      search(limit: "4")
      expect(json[:meta][:nextCursor]).to match(/\A[A-Za-z0-9_\-]+--[0-9a-f]+\z/)
    end
  end

  describe "watched" do
    let(:user) { create(:user) }
    let!(:watched) { create(:property) }
    let!(:unwatched) { create(:property) }

    before do
      WatchlistItem.create!(user:, property: watched)
      WatchlistItem.create!(user: create(:user), property: unwatched) # someone else's
    end

    it "is true only for the signed-in user's own watched properties" do
      sign_in_as(user)
      search

      flags = json[:data].to_h { |row| [ row[:id], row[:watched] ] }
      expect(flags).to eq(watched.id => true, unwatched.id => false)
    end

    it "is false for everything when signed out" do
      search
      expect(json[:data].pluck(:watched)).to all(be(false))
    end

    it "does not duplicate rows or change the count" do
      sign_in_as(user)
      search
      expect(json[:meta][:totalCount]).to eq(2)
    end
  end

  describe "invalid params (422)" do
    def expect_422(params, field)
      search(params)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error]).to include(code: "validation_failed", message: "Validation failed")
      expect(json[:error][:details]).to have_key(field)
    end

    it("rejects minPrice greater than maxPrice") { expect_422({ minPrice: "900000", maxPrice: "100000" }, :maxPrice) }
    it("rejects a non-numeric minBedrooms") { expect_422({ minBedrooms: "banana" }, :minBedrooms) }
    it("rejects a negative price") { expect_422({ minPrice: "-1" }, :minPrice) }
    it("rejects a limit above the cap") { expect_422({ limit: "51" }, :limit) }
    it("rejects a limit of zero") { expect_422({ limit: "0" }, :limit) }
    it("rejects an unknown sort") { expect_422({ sort: "random" }, :sort) }
    it("rejects an unknown property type") { expect_422({ propertyTypes: [ "castle" ] }, :propertyTypes) }
    it("rejects a non-boolean toggle") { expect_422({ excludeUnderOffer: "yes" }, :excludeUnderOffer) }
    it("rejects a q over 100 characters") { expect_422({ q: "a" * 101 }, :q) }
    it("rejects an array where one value is expected") { expect_422({ minPrice: [ "1" ] }, :minPrice) }
    it("rejects a NUL byte instead of failing with a 500") { expect_422({ q: "ab\u0000c" }, :q) }
    it("rejects a hash for property types") { expect_422({ propertyTypes: { a: "house" } }, :propertyTypes) }
    it("rejects a garbage cursor") { expect_422({ cursor: "not-a-cursor" }, :cursor) }

    it "rejects a tampered cursor" do
      create_list(:property, 3)
      search(limit: "1")
      payload, digest = json[:meta][:nextCursor].split("--")
      forged = Base64.urlsafe_encode64({ s: "newest", v: [ 0, 1 ] }.to_json, padding: false)

      expect_422({ cursor: "#{forged}--#{digest}" }, :cursor)
      expect_422({ cursor: "#{payload}--#{digest.reverse}" }, :cursor)
    end

    it "rejects a cursor issued for a different sort" do
      create_list(:property, 3)
      search(limit: "1")
      expect_422({ cursor: json[:meta][:nextCursor], sort: "price_asc" }, :cursor)
    end

    it "reports every bad param at once" do
      search(minBedrooms: "x", sort: "y", limit: "999")
      expect(json[:error][:details].keys).to contain_exactly(:minBedrooms, :sort, :limit)
    end
  end

  it "runs the same number of queries however many rows it returns (no N+1)" do
    user = create(:user)
    sign_in_as(user)
    create_list(:property, 2).each { |property| WatchlistItem.create!(user:, property:) }

    count_queries = lambda do
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { search }
      queries
    end

    few = count_queries.call
    create_list(:property, 15)
    expect(count_queries.call).to eq(few)
  end
end
