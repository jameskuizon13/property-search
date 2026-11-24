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

  MIN_SECRET_BYTES = 32

  # JWT_SECRET when set (at least 32 bytes, checked at boot by
  # config/initializers/auth_token.rb). Otherwise a key derived from
  # secret_key_base for this one purpose, rather than reusing it directly.
  def secret
    ENV.fetch("JWT_SECRET") { Rails.application.key_generator.generate_key("auth/jwt", 64) }
  end

  # A short HS256 key can be brute-forced offline from any user's own cookie,
  # after which every account's token can be forged. Fail fast instead.
  def validate_secret!
    return if secret.bytesize >= MIN_SECRET_BYTES

    raise ArgumentError, "JWT_SECRET must be at least #{MIN_SECRET_BYTES} bytes (e.g. `bin/rails secret`)"
  end
end
