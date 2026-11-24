# Issues and verifies the HS256 JWT carried in the `auth` cookie.
# The same code path authenticates REST requests and ActionCable connections.
module AuthToken
  ALGORITHM = "HS256".freeze
  TTL = 24.hours
  COOKIE_NAME = :auth

  module_function

  def encode(user, now: Time.current)
    payload = { sub: user.id.to_s, iat: now.to_i, exp: (now + TTL).to_i }
    JWT.encode(payload, secret, ALGORITHM)
  end

  # Returns the user id from a valid token, or nil for anything else
  # (missing, malformed, tampered, expired, or signed with another algorithm).
  def decode(token)
    return nil if token.blank?

    payload, _header = JWT.decode(
      token, secret, true,
      algorithm: ALGORITHM,
      required_claims: %w[sub iat exp],
      verify_expiration: true,
      verify_iat: true
    )
    return nil unless payload["exp"].is_a?(Integer) && payload["iat"].is_a?(Integer)
    return nil if payload["exp"] - payload["iat"] > TTL.to_i # never longer-lived than we issue
    return nil unless payload["sub"].is_a?(String) && payload["sub"].match?(/\A[1-9]\d*\z/)

    payload["sub"].to_i
  rescue JWT::DecodeError
    nil
  end

  # Returns the User for a valid token whose user still exists, or nil.
  def user_from(token)
    id = decode(token)
    id && User.find_by(id:)
  end

  def cookie_options(token)
    {
      value: token,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?,
      path: "/",
      expires: TTL.from_now
    }
  end

  def secret
    ENV.fetch("JWT_SECRET") { Rails.application.secret_key_base }
  end
end
