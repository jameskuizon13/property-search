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

  describe "search" do
    # sort=bogus is a cheap 422: the throttle counts it like any search.
    def search(headers = {}) = get("/api/v1/properties", params: { sort: "bogus" }, headers: json_headers.merge(headers))

    it "throttles the 121st search in a minute from one IP" do
      120.times { search }
      expect(response).to have_http_status(:unprocessable_content)

      search

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to eq("55")
      expect(json).to eq(error: { code: "rate_limited", message: "Too many requests" })
    end

    it "counts HEAD requests and the .json suffix as searches" do
      60.times { head("/api/v1/properties", params: { sort: "bogus" }, headers: json_headers) }
      59.times { get("/api/v1/properties.json", params: { sort: "bogus" }, headers: json_headers) }
      search
      expect(response).to have_http_status(:unprocessable_content)
      search
      expect(response).to have_http_status(:too_many_requests)
    end

    it "keys searches by IP" do
      120.times { search }
      search("REMOTE_ADDR" => "198.51.100.7")
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "watchlist writes" do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }

    def unwatch(as:) = delete("/api/v1/watchlist/1", headers: json_headers.merge(auth_cookie(as)))

    def auth_cookie(user) = { "Cookie" => "#{AuthToken::COOKIE_NAME}=#{AuthToken.encode(user)}" }

    it "throttles a user's 61st write in a minute, not another user on the same IP" do
      60.times { unwatch(as: user) }
      expect(response).to have_http_status(:no_content)

      unwatch(as: user)
      expect(response).to have_http_status(:too_many_requests)
      expect(json[:error][:code]).to eq("rate_limited")

      unwatch(as: other_user)
      expect(response).to have_http_status(:no_content)
    end

    it "counts PUT and DELETE together" do
      30.times { put("/api/v1/watchlist/0", headers: json_headers.merge(auth_cookie(user))) }
      30.times { unwatch(as: user) }
      unwatch(as: user)
      expect(response).to have_http_status(:too_many_requests)
    end

    it "doesn't count reading the watchlist" do
      70.times { get("/api/v1/watchlist", headers: json_headers.merge(auth_cookie(user))) }
      unwatch(as: user)
      expect(response).to have_http_status(:no_content)
    end

    it "doesn't key requests without a valid token by user" do
      61.times { delete("/api/v1/watchlist/1", headers: json_headers.merge("Cookie" => "auth=garbage")) }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # Request specs can't send these paths as-is (the test client tidies the
  # URL first), so check each rule's key on a raw Rack request. A real server
  # routes all of these to the same action.
  describe "path spellings the router treats as the same" do
    def key(rule, method, path, cookie: nil)
      env = Rack::MockRequest.env_for(path, method:, "REMOTE_ADDR" => "203.0.113.5")
      env["HTTP_COOKIE"] = cookie if cookie
      Rack::Attack.throttles.fetch(rule).block.call(Rack::Attack::Request.new(env))
    end

    it "keys every spelling of the search path" do
      [ "/api/v1/properties", "/api/v1/properties/", "/api/v1//properties", "/api//v1/properties//",
        "/api/v1/properties.json" ].each do |path|
        expect(key("search/ip", "GET", path)).to eq("203.0.113.5"), path
      end
      expect(key("search/ip", "GET", "/api/v1/properties/42")).to be_nil
    end

    it "keys every spelling of a watchlist write" do
      cookie = "#{AuthToken::COOKIE_NAME}=#{AuthToken.encode(create(:user, id: 77))}"
      [ "/api/v1/watchlist/1", "/api/v1/watchlist/1/", "/api/v1//watchlist//1" ].each do |path|
        expect(key("watchlist/user", "DELETE", path, cookie:)).to eq("user:77"), path
      end
      expect(key("watchlist/user", "GET", "/api/v1/watchlist", cookie:)).to be_nil
    end
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
