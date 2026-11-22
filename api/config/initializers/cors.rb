# The Vite dev server proxies /api, so CORS only matters when the frontend
# is served from a different origin (e.g. a deployed SPA).
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_ORIGIN") { "http://localhost:5173" }.split(",")

    resource "/api/*",
      headers: :any,
      expose: %w[ETag],
      methods: %i[get post put patch delete options head]
  end
end
