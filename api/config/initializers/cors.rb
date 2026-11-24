# The Vite dev server proxies /api, so CORS only matters when the frontend
# is served from a different origin (e.g. app. and api. subdomains).
# credentials: true lets the browser send the HttpOnly auth cookie; it is
# only allowed because the origin list is explicit (never a wildcard).
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*Rails.configuration.x.frontend_origins)

    resource "/api/*",
      headers: %w[Accept Content-Type],
      expose: %w[ETag Retry-After],
      methods: %i[get post put patch delete options head],
      credentials: true
  end
end
