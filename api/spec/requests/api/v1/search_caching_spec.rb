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

  # Rails' own Rack::ETag hashes the rendered body, so a 304 means the body
  # is byte-for-byte the same; there is no ETag of our own to keep in step.
  describe "ETag" do
    it "answers 304 when the body hasn't changed" do
      etag = search
      expect(response.headers["Cache-Control"]).to include("private")

      search(etag:)

      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_empty
    end

    it "answers 200 with the new body when anything in it changed" do
      etag = search(as: user)
      create(:watchlist_item, user:, property:)

      search(etag:, as: user)

      expect(response).to have_http_status(:ok)
      expect(json[:data].find { |row| row[:id] == property.id }[:watched]).to be(true)
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
