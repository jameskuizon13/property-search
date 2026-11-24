require "rails_helper"

# In production, errors that never reach a controller's rescue_from are
# rendered by JsonExceptionsApp. Test env shows detailed exceptions, so switch
# to production-style handling for these examples.
RSpec.describe "Error envelope outside controllers", type: :request do
  around do |example|
    env_config = Rails.application.env_config
    original = env_config.slice("action_dispatch.show_exceptions", "action_dispatch.show_detailed_exceptions")
    env_config["action_dispatch.show_exceptions"] = :all
    env_config["action_dispatch.show_detailed_exceptions"] = false
    example.run
  ensure
    env_config.merge!(original)
  end

  it "renders an unknown route as a JSON 404" do
    get "/api/v1/does-not-exist", headers: json_headers

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("application/json")
    expect(json).to eq(error: { code: "not_found", message: "Not Found" })
  end

  it "renders malformed JSON as a JSON 400" do
    post "/api/v1/auth/login", params: '{"email":', headers: json_headers

    expect(response).to have_http_status(:bad_request)
    expect(json[:error][:code]).to eq("bad_request")
  end

  it "renders an invalid Content-Type as a JSON 406" do
    post "/api/v1/auth/login", params: "x", headers: json_headers.merge("Content-Type" => "not a mime type")

    expect(response).to have_http_status(:not_acceptable)
    expect(json).to eq(error: { code: "not_acceptable", message: "Not Acceptable" })
  end

  it "does not 500 when Client-IP and X-Forwarded-For disagree" do
    get "/api/v1/me", headers: json_headers.merge("X-Forwarded-For" => "198.51.100.1", "Client-IP" => "198.51.100.2")

    expect(response).to have_http_status(:unauthorized)
    expect(json[:error][:code]).to eq("unauthorized")
  end

  it "renders an unhandled exception as a JSON 500 with no internals" do
    allow_any_instance_of(Api::V1::MeController).to receive(:show).and_raise(RuntimeError, "SELECT secret FROM users")
    sign_in_as(create(:user))

    get "/api/v1/me", headers: json_headers

    expect(response).to have_http_status(:internal_server_error)
    expect(json).to eq(error: { code: "internal_error", message: "Internal Server Error" })
    expect(response.body).not_to include("SELECT")
  end
end
