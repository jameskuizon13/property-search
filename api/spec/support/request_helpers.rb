module RequestHelpers
  def json
    JSON.parse(response.body, symbolize_names: true)
  end

  def frontend_origin
    Rails.configuration.x.frontend_origins.first
  end

  # Headers for a JSON request from the web app. The Origin header is what the
  # CSRF check needs on POST/PUT/PATCH/DELETE; omit it to prove the 403.
  def json_headers(origin: frontend_origin)
    headers = { "Accept" => "application/json", "Content-Type" => "application/json" }
    headers["Origin"] = origin if origin
    headers
  end

  # Puts a valid auth cookie in the rack-test cookie jar.
  def sign_in_as(user, token: AuthToken.encode(user))
    cookies[AuthToken::COOKIE_NAME] = token
  end

  def set_cookie_header
    Array(response.headers["set-cookie"]).join("\n")
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
end
