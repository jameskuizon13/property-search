module Api
  module V1
    class MeController < BaseController
      before_action :authenticate!

      # GET /api/v1/me
      def show
        render json: { data: UserResource.new(current_user).to_h }
      end
    end
  end
end
