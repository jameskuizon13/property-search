module Api
  module V1
    class PropertyTypesController < BaseController
      # GET /api/v1/property_types
      # Public. The enum list in display order, so the UI never hard-codes it.
      # A constant list, so browsers and proxies may keep it for an hour
      # (HTTP caching beats a Redis copy of a Ruby constant).
      def index
        expires_in 1.hour, public: true
        data = Property::PROPERTY_TYPES.map { |value, label| { value:, label: } }
        render json: { data: }
      end
    end
  end
end
