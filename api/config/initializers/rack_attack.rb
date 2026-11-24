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

  throttle("api/ip", limit: 300, period: 5.minutes) do |req|
    client_ip(req) if req.path.start_with?("/api/")
  end

  throttle("auth/ip", limit: 10, period: 1.minute) do |req|
    client_ip(req) if req.post? && req.path.start_with?("/api/v1/auth")
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
