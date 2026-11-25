require "rails_helper"

RSpec.describe "GET /api/v1/property_types", type: :request do
  it "lists every property type with its label, in display order, without signing in" do
    get "/api/v1/property_types", headers: json_headers

    expect(response).to have_http_status(:ok)
    expect(json[:data]).to eq([
      { value: "house", label: "House" },
      { value: "apartment_unit", label: "Apartment & Unit" },
      { value: "townhouse", label: "Townhouse" },
      { value: "villa", label: "Villa" },
      { value: "land", label: "Land" },
      { value: "acreage", label: "Acreage" },
      { value: "rural", label: "Rural" },
      { value: "block_of_units", label: "Block of Units" },
      { value: "retirement_living", label: "Retirement Living" }
    ])
  end

  it "lets browsers and proxies cache it for an hour" do
    get "/api/v1/property_types", headers: json_headers
    expect(response.headers["Cache-Control"]).to include("public", "max-age=3600")
  end

  it "lists exactly the model's enum values (the CHECK is covered in the model spec)" do
    get "/api/v1/property_types", headers: json_headers
    expect(json[:data].pluck(:value)).to eq(Property.property_types.values)
  end
end
