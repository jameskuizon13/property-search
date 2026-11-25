module Api
  module V1
    class BaseController < ApplicationController
      include ActionController::Cookies

      SAFE_METHODS = %w[GET HEAD OPTIONS].freeze
      PROPERTY_ID = /\A[1-9]\d{0,18}\z/

      # CSRF: the auth cookie is sent automatically, so every request that
      # changes data must come from the web app's origin. SameSite=Lax is the
      # first layer; this check is the second.
      before_action :verify_origin!

      private

      # A paged list in the shared envelope: { data: [...], meta: {...} },
      # with meta keys camelCased like every other JSON key.
      def render_page(resource, meta)
        render json: {
          data: resource.serializable_hash,
          meta: meta.transform_keys { |key| key.to_s.camelize(:lower) }
        }
      end

      def current_user
        return @current_user if defined?(@current_user)

        @current_user = AuthToken.user_from(cookies[AuthToken::COOKIE_NAME])
      end

      def authenticate!
        render_error :unauthorized, "unauthorized", "You need to sign in" unless current_user
      end

      def sign_in(user)
        cookies[AuthToken::COOKIE_NAME] = AuthToken.cookie_options(AuthToken.encode(user))
        @current_user = user
      end

      def sign_out
        cookies.delete(AuthToken::COOKIE_NAME, path: "/", same_site: :lax, secure: Rails.env.production?)
        @current_user = nil
      end

      # A property id from the URL: a plain positive integer of up to 19
      # digits, else 404. Rails treats a value past the bigint max as not
      # found. Without this check, "12abc" would be cast to 12 and act on (or
      # show) another property.
      def property_id(raw)
        raise ActiveRecord::RecordNotFound.new("Property not found", "Property") unless PROPERTY_ID.match?(raw)

        raw.to_i
      end

      def verify_origin!
        return if SAFE_METHODS.include?(request.method)
        return if Rails.configuration.x.frontend_origins.include?(request.origin)

        render_error :forbidden, "forbidden_origin", "Request origin not allowed"
      end
    end
  end
end
