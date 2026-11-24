module Api
  module V1
    class AuthController < BaseController
      # Two signups for the same email at once: the second passes validation
      # but hits the unique index. Report it like the validation would.
      rescue_from ActiveRecord::RecordNotUnique do
        render_error :unprocessable_content, "validation_failed", "Validation failed",
                     { email: [ "has already been taken" ] }
      end

      # POST /api/v1/auth/signup
      def signup
        user = User.create!(string_params(:email, :password, :name))
        sign_in(user)
        render json: { data: UserResource.new(user).to_h }, status: :created
      end

      # POST /api/v1/auth/login
      def login
        credentials = string_params(:email, :password)
        email = credentials.require(:email)
        password = credentials.require(:password)

        # authenticate_by takes the same time whether or not the email exists.
        user = User.authenticate_by(email:, password:)
        return render_error(:unauthorized, "invalid_credentials", "Invalid email or password") unless user

        sign_in(user)
        render json: { data: UserResource.new(user).to_h }
      end

      # DELETE /api/v1/auth/logout
      # Idempotent: always clears the cookie, even when it is expired or
      # tampered, so a dead cookie never lingers in the browser.
      def logout
        user = current_user
        sign_out
        # Closes this user's sockets on every device; other devices still hold
        # a valid cookie and simply reconnect (see README trade-offs).
        # Best effort: it publishes through Redis, and if that fails the
        # cleared cookie must still reach the browser. An exception here would
        # skip writing it (the cookie middleware sits inside the error page),
        # leaving a shared computer signed in. Rails.error.handle reports and
        # swallows the error.
        Rails.error.handle(context: { action: "logout_disconnect" }) do
          ActionCable.server.remote_connections.where(current_user: user).disconnect
        end if user
        head :no_content
      end
    end
  end
end
