module Api
  module V1
    class PropertyTypesController < BaseController
      # GET /api/v1/property_types
      # Public. The enum list in display order, so the UI never hard-codes it.
      def index
        data = Property::PROPERTY_TYPES.map { |value, label| { value:, label: } }
        render json: { data: }
      end
    end
  end
end
