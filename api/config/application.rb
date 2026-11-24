require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module PropertySearch
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # client_ip.rb and json_exceptions_app.rb are required at boot (below), so
    # Zeitwerk must not manage them too.
    config.autoload_lib(ignore: %w[assets tasks client_ip.rb json_exceptions_app.rb])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # API mode has no cookie jar; the JWT lives in an HttpOnly cookie.
    config.middleware.use ActionDispatch::Cookies

    # Web origins allowed by CORS, ActionCable and the Origin (CSRF) check.
    config.x.frontend_origins = ENV.fetch("FRONTEND_ORIGIN") { "http://localhost:5173" }.split(",").map(&:strip)

    # Load balancers whose X-Forwarded-For can be believed when keying rate
    # limits (see lib/client_ip.rb). Empty by default: trust nobody.
    require_relative "../lib/client_ip"
    config.x.trusted_proxies = ClientIp.parse(ENV["TRUSTED_PROXIES"])

    # Rails raises IpSpoofAttackError when Client-IP and X-Forwarded-For
    # disagree. It fires in middleware above the exceptions app (so it's an
    # empty 500, outside the JSON envelope) and before rack-attack. Nothing
    # here relies on request.remote_ip: rate limits use ClientIp instead.
    config.action_dispatch.ip_spoofing_check = false

    # 404s for unknown routes and unhandled 500s use the JSON error envelope.
    require_relative "../lib/json_exceptions_app"
    config.exceptions_app = JsonExceptionsApp.new
  end
end
