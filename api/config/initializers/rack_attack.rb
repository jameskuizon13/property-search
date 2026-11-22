# Throttling rules. Counters live in Rails.cache (Redis outside of test).
# The rack-attack railtie inserts the middleware automatically.
class Rack::Attack
  throttle("api/ip", limit: 300, period: 5.minutes) do |req|
    req.ip if req.path.start_with?("/api/")
  end

  throttle("auth/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.post? && req.path.start_with?("/api/v1/auth")
  end

  self.throttled_responder = lambda do |req|
    match_data = req.env["rack.attack.match_data"] || {}
    retry_after = (match_data[:period] || 60).to_s
    body = { error: { code: "rate_limited", message: "Too many requests" } }.to_json
    [ 429, { "Content-Type" => "application/json", "Retry-After" => retry_after }, [ body ] ]
  end
end
