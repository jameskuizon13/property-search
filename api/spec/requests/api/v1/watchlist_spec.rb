require "rails_helper"

RSpec.describe "Watchlist API", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:property) { create(:property) }

  def watch(property, by: user, at: Time.current)
    WatchlistItem.create!(user: by, property:, created_at: at)
  end

  def list(params = {})
    get "/api/v1/watchlist", params:, headers: json_headers
  end

  def put_watch(id, headers: json_headers, params: nil)
    put "/api/v1/watchlist/#{id}", params: params&.to_json, headers:
  end

  def delete_watch(id, headers: json_headers)
    delete "/api/v1/watchlist/#{id}", headers:
  end

  def ids = json[:data].pluck(:id)

  describe "authentication" do
    it "returns 401 on every endpoint without a cookie" do
      list
      expect(response).to have_http_status(:unauthorized)
      expect(json[:error][:code]).to eq("unauthorized")

      put_watch(property.id)
      expect(response).to have_http_status(:unauthorized)

      delete_watch(property.id)
      expect(response).to have_http_status(:unauthorized)
      expect(WatchlistItem.count).to eq(0)
    end

    it "returns 401 with an expired token" do
      sign_in_as(user)
      travel_to(25.hours.from_now) { put_watch(property.id) }
      expect(response).to have_http_status(:unauthorized)
      expect(WatchlistItem.count).to eq(0)
    end

    it "returns 403 for a write from a foreign origin (CSRF), before anything changes" do
      sign_in_as(user)
      put_watch(property.id, headers: json_headers(origin: "https://evil.example"))
      expect(response).to have_http_status(:forbidden)
      expect(WatchlistItem.count).to eq(0)

      watch(property)
      delete_watch(property.id, headers: json_headers(origin: nil))
      expect(response).to have_http_status(:forbidden)
      expect(WatchlistItem.count).to eq(1)
    end
  end

  it "allows a PUT preflight from the web app's origin, with credentials" do
    options "/api/v1/watchlist/#{property.id}",
            headers: { "Origin" => frontend_origin, "Access-Control-Request-Method" => "PUT" }

    expect(response.headers["Access-Control-Allow-Origin"]).to eq(frontend_origin)
    expect(response.headers["Access-Control-Allow-Methods"]).to include("PUT")
    expect(response.headers["Access-Control-Allow-Credentials"]).to eq("true")
  end

  describe "GET /api/v1/watchlist" do
    before { sign_in_as(user) }

    it "returns an empty page when nothing is watched" do
      list
      expect(response).to have_http_status(:ok)
      expect(json).to eq(data: [], meta: { limit: 20, hasMore: false, totalCount: 0 })
    end

    it "returns watched properties in the search shape, all with watched: true" do
      watch(property)
      list

      expect(response).to have_http_status(:ok)
      row = json[:data].first
      expect(row).to include(id: property.id, streetAddress: property.street_address, status: "for_sale", watched: true)
      expect(row.keys).not_to include(:watchlistItemId, :watchedAt, :lockVersion)
      expect(json[:meta]).to eq(limit: 20, hasMore: false, totalCount: 1)
    end

    it "orders by date added, newest first (not by listing date)" do
      old_listing = create(:property, listed_at: 1.year.ago)
      new_listing = create(:property, listed_at: 1.day.ago)
      watch(new_listing, at: 2.days.ago)
      watch(old_listing, at: 1.hour.ago)

      list
      expect(ids).to eq([ old_listing.id, new_listing.id ])
    end

    it "keeps sold and withdrawn properties, with their status" do
      sold = create(:property, status: "sold")
      withdrawn = create(:property, status: "withdrawn")
      watch(sold, at: 2.minutes.ago)
      watch(withdrawn, at: 1.minute.ago)

      list
      expect(json[:data].map { |row| [ row[:id], row[:status] ] }).to eq([ [ withdrawn.id, "withdrawn" ], [ sold.id, "sold" ] ])
    end

    it "returns only the signed-in user's items (no IDOR)" do
      mine = create(:property)
      theirs = create(:property)
      watch(mine)
      watch(theirs, by: other_user)

      list
      expect(ids).to eq([ mine.id ])
      expect(json[:meta][:totalCount]).to eq(1)
    end

    it "ignores a user_id param" do
      watch(create(:property), by: other_user)
      list(user_id: other_user.id, userId: other_user.id)
      expect(ids).to eq([])
    end

    it "walks every item exactly once with the cursor, including same-microsecond ties" do
      at = Time.zone.parse("2026-11-20 10:00:00.123456")
      items = Array.new(5) { |i| watch(create(:property), at: i < 3 ? at : at - (i * 0.000001)) }

      seen = []
      cursor = nil
      loop do
        list({ limit: "2", cursor: }.compact)
        expect(response).to have_http_status(:ok)
        expect(json[:meta].key?(:totalCount)).to be(cursor.nil?)
        seen.concat(ids)
        break unless json[:meta][:hasMore]

        cursor = json[:meta][:nextCursor]
      end

      expected = items.sort_by { |item| [ item.created_at, item.id ] }.reverse.map(&:property_id)
      expect(seen).to eq(expected)
    end

    it "counts the whole watchlist on the first page when there is more" do
      3.times { watch(create(:property)) }
      list(limit: "2")
      expect(json[:meta]).to include(limit: 2, hasMore: true, totalCount: 3)
    end

    it "returns 422 for a bad limit, a forged cursor or a search cursor" do
      list(limit: "0")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error][:details].keys).to eq([ :limit ])

      list(limit: "51")
      expect(response).to have_http_status(:unprocessable_content)

      list(limit: [ "1" ])
      expect(response).to have_http_status(:unprocessable_content)

      list(cursor: "forged")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error][:details].keys).to eq([ :cursor ])

      list(cursor: Properties::Cursor.encode(sort: "newest", record: property))
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "treats another user's cursor as a position in your own list, so it leaks nothing" do
      3.times { watch(create(:property), by: other_user) }
      sign_in_as(other_user)
      list(limit: "1")
      their_cursor = json[:meta][:nextCursor]

      sign_in_as(user)
      list(cursor: their_cursor)
      expect(response).to have_http_status(:ok)
      expect(ids).to eq([])
    end

    it "runs the same number of queries however many rows it returns (no N+1)" do
      2.times { watch(create(:property)) }

      count_queries = lambda do
        queries = 0
        counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { list(limit: "50") }
        queries
      end

      few = count_queries.call
      15.times { watch(create(:property)) }
      expect(count_queries.call).to eq(few)
    end
  end

  describe "PUT /api/v1/watchlist/:property_id" do
    before { sign_in_as(user) }

    it "watches the property: 201 with the property, watched: true" do
      put_watch(property.id)

      expect(response).to have_http_status(:created)
      expect(json[:data]).to include(id: property.id, watched: true)
      expect(user.watchlist_items.pluck(:property_id)).to eq([ property.id ])
    end

    it "is idempotent: a second PUT returns 200 and keeps one row" do
      put_watch(property.id)
      put_watch(property.id)

      expect(response).to have_http_status(:ok)
      expect(json[:data]).to include(id: property.id, watched: true)
      expect(WatchlistItem.where(user:, property:).count).to eq(1)
    end

    # create_or_find_by! inserts first, so an existing row is exactly what a
    # concurrent PUT that won the race leaves behind: the unique index raises
    # and the existing row is returned instead of a 500.
    it "returns the existing row when the insert hits the unique index" do
      existing = watch(property, at: 1.day.ago)
      put_watch(property.id)

      expect(response).to have_http_status(:ok)
      expect(WatchlistItem.sole).to eq(existing)
      expect(WatchlistItem.sole.created_at).to be_within(1.second).of(1.day.ago)
    end

    it "lets a user watch a property someone else already watches" do
      watch(property, by: other_user)
      put_watch(property.id)

      expect(response).to have_http_status(:created)
      expect(WatchlistItem.where(property:).pluck(:user_id)).to contain_exactly(user.id, other_user.id)
    end

    it "is not limited to active listings" do
      sold = create(:property, status: "sold")
      put_watch(sold.id)
      expect(response).to have_http_status(:created)
    end

    it "always watches for the signed-in user, ignoring a user_id in the body" do
      put_watch(property.id, params: { user_id: other_user.id, userId: other_user.id })

      expect(response).to have_http_status(:created)
      expect(WatchlistItem.sole.user_id).to eq(user.id)
    end

    it "returns 404 for a property that doesn't exist" do
      put_watch(0)
      expect(response).to have_http_status(:not_found)
      expect(json).to eq(error: { code: "not_found", message: "Property not found" })

      put_watch(Property.maximum(:id).to_i + 1000)
      expect(response).to have_http_status(:not_found)
      expect(WatchlistItem.count).to eq(0)
    end

    it "returns 404 for an id that isn't a plain integer, instead of casting it" do
      [ "#{property.id}abc", "-#{property.id}", "#{property.id}.0", "1e3", "99999999999999999999" ].each do |id|
        put_watch(id)
        expect(response).to have_http_status(:not_found), "expected 404 for #{id.inspect}"
      end
      expect(WatchlistItem.count).to eq(0)
    end

    it "returns 404 when the property is deleted between the lookup and the insert" do
      property.delete
      allow(Property).to receive(:find).and_return(property)

      put_watch(property.id)
      expect(response).to have_http_status(:not_found)
      expect(json[:error][:code]).to eq("not_found")
    end
  end

  describe "DELETE /api/v1/watchlist/:property_id" do
    before { sign_in_as(user) }

    it "unwatches the property: 204" do
      watch(property)
      delete_watch(property.id)

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty
      expect(WatchlistItem.count).to eq(0)
    end

    it "is idempotent: 204 when not watched, or when the property doesn't exist" do
      delete_watch(property.id)
      expect(response).to have_http_status(:no_content)

      delete_watch(Property.maximum(:id).to_i + 1000)
      expect(response).to have_http_status(:no_content)
    end

    it "never removes another user's item (no IDOR)" do
      watch(property, by: other_user)
      delete_watch(property.id)

      expect(response).to have_http_status(:no_content)
      expect(WatchlistItem.where(user: other_user, property:)).to exist
    end

    it "only removes that property from the user's own list" do
      kept = create(:property)
      watch(property)
      watch(kept)
      watch(property, by: other_user)

      delete_watch(property.id)
      expect(user.watchlist_items.pluck(:property_id)).to eq([ kept.id ])
      expect(other_user.watchlist_items.pluck(:property_id)).to eq([ property.id ])
    end

    it "returns 404 for an id that isn't a plain integer, instead of casting it" do
      watch(property)
      [ "#{property.id}abc", "#{property.id}.0" ].each do |id|
        delete_watch(id)
        expect(response).to have_http_status(:not_found), "expected 404 for #{id.inspect}"
      end
      expect(WatchlistItem.count).to eq(1)
    end
  end
end
