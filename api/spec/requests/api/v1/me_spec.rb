require "rails_helper"

RSpec.describe "GET /api/v1/me", type: :request do
  let(:user) { create(:user) }

  it "returns the current user" do
    sign_in_as(user)
    get "/api/v1/me", headers: json_headers

    expect(response).to have_http_status(:ok)
    expect(json).to eq(data: { id: user.id, email: user.email, name: user.name, role: "user" })
  end

  it "includes the admin role so the UI can show the admin link" do
    sign_in_as(create(:user, role: "admin"))
    get "/api/v1/me", headers: json_headers
    expect(json[:data][:role]).to eq("admin")
  end

  it "returns 401 without a cookie" do
    get "/api/v1/me", headers: json_headers

    expect(response).to have_http_status(:unauthorized)
    expect(json).to eq(error: { code: "unauthorized", message: "You need to sign in" })
  end

  it "rejects a token past its 24-hour exp" do
    sign_in_as(user)
    travel_to(25.hours.from_now) do
      get "/api/v1/me", headers: json_headers
    end
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a tampered token" do
    sign_in_as(user, token: AuthToken.encode(user).chop)
    get "/api/v1/me", headers: json_headers
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects an alg: none token" do
    token = JWT.encode({ sub: user.id.to_s, iat: Time.now.to_i, exp: 1.hour.from_now.to_i }, nil, "none")
    sign_in_as(user, token:)
    get "/api/v1/me", headers: json_headers
    expect(response).to have_http_status(:unauthorized)
  end

  it "ignores a Bearer header; only the cookie authenticates" do
    get "/api/v1/me", headers: json_headers.merge("Authorization" => "Bearer #{AuthToken.encode(user)}")
    expect(response).to have_http_status(:unauthorized)
  end
end
