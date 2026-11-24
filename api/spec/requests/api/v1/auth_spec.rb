require "rails_helper"

RSpec.describe "Auth", type: :request do
  let(:password) { "correct horse battery" }

  describe "POST /api/v1/auth/signup" do
    let(:params) { { email: "New@Example.com", password:, name: "New User" } }

    it "creates the user, returns 201 and sets the auth cookie" do
      expect {
        post "/api/v1/auth/signup", params: params.to_json, headers: json_headers
      }.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json[:data]).to include(email: "new@example.com", name: "New User")
      expect(json[:data].keys).to contain_exactly(:id, :email, :name)
      expect(set_cookie_header).to match(/\Aauth=[^;]+/)
      expect(set_cookie_header).to match(/;\s*httponly/i)
      expect(set_cookie_header).to match(/;\s*samesite=lax/i)
      expect(set_cookie_header).to match(/;\s*path=\//i)
    end

    it "returns 422 with field errors for an invalid user" do
      post "/api/v1/auth/signup", params: { email: "bad", password: "short", name: "" }.to_json, headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error][:code]).to eq("validation_failed")
      expect(json[:error][:details].keys).to include(:email, :password, :name)
      expect(set_cookie_header).not_to include("auth=")
    end

    it "rejects an email that differs only by case" do
      create(:user, email: "new@example.com")
      post "/api/v1/auth/signup", params: params.to_json, headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error][:details][:email]).to include("has already been taken")
    end

    it "returns 400 when a field is not a string" do
      post "/api/v1/auth/signup", params: params.merge(password: 123_456_789_012_345).to_json, headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(json[:error]).to eq(code: "bad_request", message: "password must be a string")
    end

    %i[email password name].each do |field|
      it "returns 400 when #{field} contains a null byte" do
        post "/api/v1/auth/signup", params: params.merge(field => "bad\u0000value@example.com").to_json, headers: json_headers

        expect(response).to have_http_status(:bad_request)
        expect(json[:error]).to eq(code: "bad_request", message: "#{field} contains a null byte")
      end
    end

    it "treats null fields as blank (422), not as a type error" do
      post "/api/v1/auth/signup", params: params.merge(name: nil).to_json, headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error][:details][:name]).to include("can't be blank")
    end

    it "drops array and hash values instead of crashing" do
      post "/api/v1/auth/signup", params: params.merge(name: [ "a" ], email: { x: 1 }).to_json, headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error][:details].keys).to include(:name, :email)
    end

    it "returns 422, not 500, when a concurrent signup wins the unique index" do
      allow(User).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
      post "/api/v1/auth/signup", params: params.to_json, headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error]).to eq(code: "validation_failed", message: "Validation failed",
                                 details: { email: [ "has already been taken" ] })
    end

    it "returns 400 in the error envelope for malformed JSON" do
      post "/api/v1/auth/signup", params: '{"email":', headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("application/json")
      expect(json[:error][:code]).to eq("bad_request")
    end

    it "ignores attributes that are not allow-listed" do
      post "/api/v1/auth/signup", params: params.merge(id: 9999, password_digest: "x").to_json, headers: json_headers

      expect(response).to have_http_status(:created)
      expect(User.last.id).not_to eq(9999)
      expect(User.last.authenticate(password)).to be_truthy
    end
  end

  describe "POST /api/v1/auth/login" do
    let!(:user) { create(:user, email: "alice@example.com", password:) }

    it "returns the user and sets an HttpOnly, SameSite=Lax cookie" do
      post "/api/v1/auth/login", params: { email: "Alice@Example.com", password: }.to_json, headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(json[:data]).to include(id: user.id, email: "alice@example.com")
      cookie = set_cookie_header
      expect(cookie).to match(/\Aauth=[^;]+/)
      expect(cookie).to match(/;\s*httponly/i)
      expect(cookie).to match(/;\s*samesite=lax/i)
      expect(cookie).to match(/;\s*path=\//i)
      expect(cookie).not_to match(/;\s*secure/i)
    end

    it "marks the cookie Secure in production" do
      allow(Rails.env).to receive(:production?).and_return(true)
      https!
      post "/api/v1/auth/login", params: { email: "alice@example.com", password: }.to_json,
                                 headers: json_headers(origin: frontend_origin)

      expect(response).to have_http_status(:ok)
      expect(set_cookie_header).to match(/;\s*secure/i)
    end

    it "sets a token that authenticates the user" do
      post "/api/v1/auth/login", params: { email: "alice@example.com", password: }.to_json, headers: json_headers
      get "/api/v1/me", headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(json[:data][:id]).to eq(user.id)
    end

    it "returns the same generic 401 for a wrong password and an unknown email" do
      post "/api/v1/auth/login", params: { email: "alice@example.com", password: "wrong password!" }.to_json, headers: json_headers
      wrong_password = [ response.status, json ]

      post "/api/v1/auth/login", params: { email: "nobody@example.com", password: }.to_json, headers: json_headers
      unknown_email = [ response.status, json ]

      expect(wrong_password).to eq(unknown_email)
      expect(wrong_password).to eq([ 401, { error: { code: "invalid_credentials", message: "Invalid email or password" } } ])
      expect(set_cookie_header).not_to include("auth=")
    end

    it "returns 400 when the password is not a string" do
      post "/api/v1/auth/login", params: { email: "alice@example.com", password: 123_456_789_012_345 }.to_json,
                                 headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(json[:error][:code]).to eq("bad_request")
    end

    it "returns 400 when the password contains a null byte" do
      post "/api/v1/auth/login", params: { email: "alice@example.com", password: "x\u0000" }.to_json, headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(json[:error][:message]).to eq("password contains a null byte")
    end

    it "returns 400 when the email contains a null byte" do
      post "/api/v1/auth/login", params: { email: "alice\u0000@example.com", password: }.to_json, headers: json_headers
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 400 when the email is an array" do
      post "/api/v1/auth/login", params: { email: [ "alice@example.com", "bob@example.com" ], password: }.to_json,
                                 headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(set_cookie_header).not_to include("auth=")
    end

    it "returns 400 when a required param is missing" do
      post "/api/v1/auth/login", params: { email: "alice@example.com" }.to_json, headers: json_headers

      expect(response).to have_http_status(:bad_request)
      expect(json[:error][:code]).to eq("parameter_missing")
    end
  end

  describe "DELETE /api/v1/auth/logout" do
    let(:user) { create(:user) }

    it "clears the cookie, disconnects the user's sockets and returns 204" do
      sign_in_as(user)
      expect(ActionCable.server.remote_connections).to receive(:where).with(current_user: user).and_call_original

      delete "/api/v1/auth/logout", headers: json_headers

      expect(response).to have_http_status(:no_content)
      expect(set_cookie_header).to match(/\Aauth=;/)
      expect(set_cookie_header).to match(/;\s*path=\//i)
      expect(set_cookie_header).to match(/max-age=0|expires=Thu, 01 Jan 1970/i)

      get "/api/v1/me", headers: json_headers
      expect(response).to have_http_status(:unauthorized)
    end

    it "is idempotent when signed out" do
      expect(ActionCable.server.remote_connections).not_to receive(:where)
      delete "/api/v1/auth/logout", headers: json_headers
      expect(response).to have_http_status(:no_content)
    end

    it "still clears an expired or tampered cookie, without touching sockets" do
      sign_in_as(user, token: AuthToken.encode(user).chop)
      expect(ActionCable.server.remote_connections).not_to receive(:where)
      delete "/api/v1/auth/logout", headers: json_headers

      expect(response).to have_http_status(:no_content)
      expect(set_cookie_header).to match(/\Aauth=;.*path=\//i)
    end
  end

  describe "Origin check (CSRF)" do
    let!(:user) { create(:user, email: "alice@example.com", password:) }
    let(:params) { { email: "alice@example.com", password: }.to_json }

    it "rejects a data-changing request from a foreign origin with 403" do
      post "/api/v1/auth/login", params:, headers: json_headers(origin: "https://evil.example")

      expect(response).to have_http_status(:forbidden)
      expect(json[:error][:code]).to eq("forbidden_origin")
      expect(set_cookie_header).not_to include("auth=")
    end

    [
      "http://localhost:5173.evil.example",
      "http://localhost:5173/",
      "http://LOCALHOST:5173",
      "http://localhost:5174",
      "https://localhost:5173",
      "null"
    ].each do |origin|
      it "rejects the look-alike origin #{origin}" do
        post "/api/v1/auth/login", params:, headers: json_headers(origin:)
        expect(response).to have_http_status(:forbidden)
      end
    end

    it "rejects a data-changing request with no Origin header" do
      post "/api/v1/auth/login", params:, headers: json_headers(origin: nil)
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects logout with a garbage cookie from a foreign origin, leaving the cookie alone" do
      sign_in_as(user, token: "garbage")
      delete "/api/v1/auth/logout", headers: json_headers(origin: "https://evil.example")

      expect(response).to have_http_status(:forbidden)
      expect(set_cookie_header).not_to include("auth=")
    end

    it "rejects a signed-in logout from a foreign origin" do
      sign_in_as(user)
      delete "/api/v1/auth/logout", headers: json_headers(origin: "https://evil.example")
      expect(response).to have_http_status(:forbidden)
    end

    it "does not check Origin on GET" do
      sign_in_as(user)
      get "/api/v1/me", headers: json_headers(origin: "https://evil.example")
      expect(response).to have_http_status(:ok)
    end
  end
end
