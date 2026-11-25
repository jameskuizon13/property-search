module Api
  module V1
    class BaseController < ApplicationController
      include ActionController::Cookies

      SAFE_METHODS = %w[GET HEAD OPTIONS].freeze

      # CSRF: the auth cookie is sent automatically, so every request that
      # changes data must come from the web app's origin. SameSite=Lax is the
      # first layer; this check is the second.
      before_action :verify_origin!

      private

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

      def verify_origin!
        return if SAFE_METHODS.include?(request.method)
        return if Rails.configuration.x.frontend_origins.include?(request.origin)

        render_error :forbidden, "forbidden_origin", "Request origin not allowed"
      end
    end
  end
end
