require "rails_helper"

RSpec.describe "Rate limiting", type: :request do
  let(:params) { { email: "nobody@example.com", password: "wrong password!" }.to_json }

  # rack-attack counts in fixed windows; start 5 s into one so the spec never
  # straddles a boundary. 300 s alignment covers both the 1-min and 5-min rules.
  around do |example|
    now = Time.now.to_i
    travel_to(Time.zone.at(now - (now % 300) + 305)) { example.run }
  end

  def login(headers = {})
    post "/api/v1/auth/login", params:, headers: json_headers.merge(headers)
  end

  it "throttles the 11th login attempt in a minute from one IP" do
    10.times do
      login
      expect(response).to have_http_status(:unauthorized)
    end

    login

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to eq("55") # what is left of the window
    expect(json).to eq(error: { code: "rate_limited", message: "Too many requests" })
  end

  it "throttles general API traffic at 300 requests per 5 minutes" do
    300.times { get "/api/v1/me", headers: json_headers }
    expect(response).to have_http_status(:unauthorized)

    get "/api/v1/me", headers: json_headers

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to eq("295")
    expect(json[:error][:code]).to eq("rate_limited")
  end

  it "counts signup and login together" do
    10.times { post "/api/v1/auth/signup", params: {}.to_json, headers: json_headers }
    login
    expect(response).to have_http_status(:too_many_requests)
  end

  it "ignores a spoofed X-Forwarded-For from an untrusted peer" do
    10.times { |i| login("X-Forwarded-For" => "198.51.100.#{i}") }
    login("X-Forwarded-For" => "198.51.100.99")
    expect(response).to have_http_status(:too_many_requests)
  end

  context "behind a trusted proxy" do
    before do
      allow(Rails.configuration.x).to receive(:trusted_proxies).and_return(ClientIp.parse("127.0.0.0/8"))
    end

    it "keys on the client address the proxy forwarded" do
      10.times { login("X-Forwarded-For" => "198.51.100.1") }
      login("X-Forwarded-For" => "198.51.100.2")
      expect(response).to have_http_status(:unauthorized)

      login("X-Forwarded-For" => "198.51.100.1")
      expect(response).to have_http_status(:too_many_requests)
    end

    it "ignores entries the client prepended before the proxy's" do
      10.times { |i| login("X-Forwarded-For" => "203.0.113.#{i}, 198.51.100.1") }
      login("X-Forwarded-For" => "203.0.113.99, 198.51.100.1")
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
