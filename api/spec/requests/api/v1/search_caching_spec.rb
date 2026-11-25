require "rails_helper"

RSpec.describe "Search caching", type: :request do
  # The test env's Rails.cache is a null store; these specs need a real one.
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:user) { create(:user) }
  let!(:property) { create(:property) }

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    create_list(:property, 2)
  end

  def search(params = {}, etag: nil, as: nil, **filters)
    params = params.merge(filters)
    headers = json_headers
    headers = headers.merge("If-None-Match" => etag) if etag
    headers = headers.merge("Cookie" => "#{AuthToken::COOKIE_NAME}=#{AuthToken.encode(as)}") if as
    get("/api/v1/properties", params:, headers:)
    response.headers["ETag"]
  end

  # SQL statements sent while the block runs, minus schema/transaction noise.
  def queries
    sql = []
    callback = ->(*, payload) { sql << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    sql
  end

  describe "ETag" do
    it "answers 304 without running the search when nothing changed" do
      etag = search
      expect(etag).to start_with("W/")
      expect(response.headers["Cache-Control"]).to include("private")

      sql = queries { search(etag:) }

      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_empty
      expect(sql.grep(/FROM "properties"/)).to be_empty
    end

    it "changes when a property changes" do
      etag = search
      property.update!(bedrooms: 5)
      search(etag:)
      expect(response).to have_http_status(:ok)
    end

    it "changes when a property is created or deleted" do
      etag = search
      create(:property)
      expect(search).not_to eq(etag)

      etag = search
      property.destroy!
      expect(search).not_to eq(etag)
    end

    it "varies by user, even with empty watchlists, and on sign-in" do
      anonymous = search
      first = search(as: user)
      second = search(as: create(:user))
      expect([ anonymous, first, second ].uniq.size).to eq(3)
    end

    it "changes when the user watches or unwatches anything" do
      etag = search(as: user)
      item = create(:watchlist_item, user:, property:)
      watched = search(as: user)
      expect(watched).not_to eq(etag)

      item.destroy!
      create(:watchlist_item, user:, property: create(:property))
      expect(search(as: user)).not_to eq(watched)
    end

    it "differs between filters, sorts, cursors and limits" do
      etags = [
        search, search(minBedrooms: 3), search(sort: "price_asc"), search(limit: 1),
        search(cursor: JSON.parse(response.body)["meta"]["nextCursor"], limit: 1)
      ]
      expect(etags.uniq.size).to eq(etags.size)
    end

    it "is shared by equivalent requests" do
      expect(search(propertyTypes: %w[villa house])).to eq(search(propertyTypes: %w[house villa]))
      expect(search(q: "f")).to eq(search)
      expect(search(limit: 20)).to eq(search)
    end

    it "never answers 304 to an invalid request" do
      etag = search
      search({ minBedrooms: "banana" }, etag:)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "totalCount" do
    def count_queries(params = {}) = queries { search(params.merge(limit: 1)) }.grep(/SELECT COUNT\(\*\) FROM "properties"/)

    it "is cached between first batches with the same filters" do
      expect(count_queries.size).to eq(1)
      expect(count_queries.size).to eq(0)
      expect(json[:meta][:totalCount]).to eq(3)
    end

    it "is recounted after a property changes" do
      count_queries
      create(:property)
      expect(count_queries.size).to eq(1)
      expect(json[:meta][:totalCount]).to eq(4)
    end

    it "is shared across users and sorts that don't change it, not across filters" do
      count_queries
      expect(queries { search({ limit: 1 }, as: user) }.grep(/SELECT COUNT\(\*\) FROM "properties"/)).to be_empty
      expect(count_queries(minBedrooms: 3).size).to eq(1)
      expect(count_queries(sort: "price_asc").size).to eq(1) # price sorts drop withheld prices
    end
  end
end
