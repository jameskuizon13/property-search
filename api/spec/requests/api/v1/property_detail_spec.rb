require "rails_helper"

RSpec.describe "GET /api/v1/properties/:id", type: :request do
  let(:property) do
    create(:property, listed_at: Time.zone.parse("2026-11-01 00:00:00"),
                      image_url: "/images/properties/house-01.webp", description: "A light-filled family home.")
  end

  def show(id = property.id)
    get "/api/v1/properties/#{id}", headers: json_headers
  end

  it "returns the list shape plus the description and history, without signing in" do
    show

    expect(response).to have_http_status(:ok)
    expect(json[:data]).to eq(
      id: property.id, streetAddress: property.street_address, suburb: "Fitzroy", state: "VIC",
      postcode: "3065", latitude: -37.798, longitude: 144.978, priceCents: 85_000_000,
      priceDisplay: "$850,000", bedrooms: 3, bathrooms: 2, carSpaces: 1, landSizeSqm: 320,
      propertyType: "house", status: "for_sale", listedAt: "2026-11-01T00:00:00.000Z",
      imageUrl: "/images/properties/house-01.webp", version: 0, watched: false,
      description: "A light-filled family home.", history: [], historyComplete: true
    )
  end

  # Changes saved together share a timestamp; the id breaks the tie, so the
  # status change (written second) comes first.
  it "lists price and status changes newest first, with prices as integer cents" do
    travel_to(Time.zone.parse("2026-11-10 09:00:00")) { property.update!(price_cents: 82_000_000) }
    travel_to(Time.zone.parse("2026-11-12 09:00:00")) do
      property.update!(price_cents: 80_000_000, price_display: "$800,000", status: "under_offer")
    end
    show

    expect(json[:data][:history].map { _1.except(:id) }).to eq(
      [
        { kind: "status_changed", from: "for_sale", to: "under_offer", createdAt: "2026-11-12T09:00:00.000Z" },
        { kind: "price_changed", from: 82_000_000, to: 80_000_000, createdAt: "2026-11-12T09:00:00.000Z" },
        { kind: "price_changed", from: 85_000_000, to: 82_000_000, createdAt: "2026-11-10T09:00:00.000Z" }
      ]
    )
  end

  # The agent hid the price on purpose; the history must not show it.
  it "leaves every amount out of the history while the price is withheld" do
    property.update!(price_cents: 82_000_000)
    property.update!(price_cents: nil, price_display: "Contact agent")
    show

    expect(json[:data][:history].map { _1.slice(:kind, :from, :to) }).to eq(
      [ { kind: "price_changed", from: nil, to: nil } ] * 2
    )
    expect(response.body).not_to include("82000000", "85000000")
  end

  it "returns the 20 most recent changes, and says when older ones were left out" do
    create_list(:property_event, 20, property:)
    show
    expect(json[:data][:history].size).to eq(20)
    expect(json[:data][:historyComplete]).to be(true)

    create(:property_event, property:)
    show
    expect(json[:data][:history].size).to eq(20)
    expect(json[:data][:historyComplete]).to be(false)
  end

  it "says whether the signed-in user watches it" do
    user = create(:user)
    sign_in_as(user)
    show
    expect(json[:data][:watched]).to be(false)

    create(:watchlist_item, user:, property:)
    show
    expect(json[:data][:watched]).to be(true)
  end

  it "answers as signed out, not 401, when the auth cookie is invalid" do
    create(:watchlist_item, property:)
    cookies[AuthToken::COOKIE_NAME] = "not-a-token"
    show

    expect(response).to have_http_status(:ok)
    expect(json[:data][:watched]).to be(false)
  end

  it "doesn't report another user's watch as yours" do
    create(:watchlist_item, property:)
    sign_in_as(create(:user))
    show

    expect(json[:data][:watched]).to be(false)
  end

  it "opens sold and withdrawn properties too, so a watched one that sold still opens" do
    property.update!(status: "sold")
    show

    expect(response).to have_http_status(:ok)
    expect(json[:data][:status]).to eq("sold")
  end

  it "returns 404 in the shared error shape for a property that doesn't exist" do
    show(Property.maximum(:id).to_i + 1)

    expect(response).to have_http_status(:not_found)
    expect(json).to eq(error: { code: "not_found", message: "Property not found" })
  end

  it "returns 404 for an id that isn't a plain integer, instead of casting it" do
    [ "#{property.id}abc", "0", "-#{property.id}", "1e3", "9" * 20, "9223372036854775808" ].each do |id|
      show(id)
      expect(response).to have_http_status(:not_found), "expected 404 for #{id.inspect}"
    end
  end

  it "doesn't route a .json-style suffix to another property" do
    get "/api/v1/properties/#{property.id}.0", headers: json_headers

    expect(response).to have_http_status(:not_found)
  end
end
