# Throttling rules. The rack-attack railtie inserts the middleware automatically.
#
# Counters get their own store rather than Rails.cache: the test env's
# Rails.cache is a :null_store, which would never count anything.
class Rack::Attack
  self.cache.store =
    if Rails.env.test?
      ActiveSupport::Cache::MemoryStore.new
    else
      ActiveSupport::Cache::RedisCacheStore.new(
        url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/0" },
        namespace: "rack-attack"
      )
    end

  # Not `req.ip`: it believes a client-supplied X-Forwarded-For.
  def self.client_ip(req) = ClientIp.call(req.env)

  # The path as the router sees it: Rails merges repeated slashes and drops a
  # trailing one, so /api/v1//properties/ reaches the same action and must
  # hit the same throttle.
  def self.route_path(req) = req.path.squeeze("/").delete_suffix("/")

  throttle("api/ip", limit: 300, period: 5.minutes) do |req|
    client_ip(req) if req.path.start_with?("/api/")
  end

  throttle("auth/ip", limit: 10, period: 1.minute) do |req|
    client_ip(req) if req.post? && req.path.start_with?("/api/v1/auth")
  end

  # Search bursts. api/ip above still caps the sustained rate. HEAD runs the
  # same query, and the router also accepts a .json suffix.
  SEARCH = %r{\A/api/v1/properties(\.json)?\z}
  throttle("search/ip", limit: 120, period: 1.minute) do |req|
    client_ip(req) if (req.get? || req.head?) && SEARCH.match?(route_path(req))
  end

  # Watchlist writes, per user rather than per IP, so one busy office or
  # household doesn't share a bucket. The middleware runs before any
  # controller, so the user comes from the token itself (signature and expiry
  # checked, no DB query). No valid token: no key here (the request 401s, and
  # api/ip still counts it).
  WATCHLIST_WRITE = %r{\A/api/v1/watchlist/[^/]+\z}
  throttle("watchlist/user", limit: 60, period: 1.minute) do |req|
    next unless (req.put? || req.delete?) && WATCHLIST_WRITE.match?(route_path(req))

    user_id = AuthToken.decode(req.cookies[AuthToken::COOKIE_NAME.to_s])
    "user:#{user_id}" if user_id
  end

  self.throttled_responder = lambda do |req|
    # Counters use fixed windows, so the wait is whatever is left of this one.
    match_data = req.env["rack.attack.match_data"] || {}
    period = match_data[:period] || 60
    now = match_data[:epoch_time] || Time.now.to_i
    retry_after = (period - (now % period)).to_s
    body = { error: { code: "rate_limited", message: "Too many requests" } }.to_json
    [ 429, { "Content-Type" => "application/json", "Retry-After" => retry_after }, [ body ] ]
  end
end
