module Api
  module V1
    class PropertiesController < BaseController
      SEARCH_PARAMS = %w[
        q minPrice maxPrice minBedrooms propertyTypes excludeUnderOffer excludePriceWithheld sort cursor limit
      ].freeze

      # GET /api/v1/properties
      # Public; signing in only adds the per-user `watched` flag.
      # No custom ETag: Rack::ETag hashes the rendered body, so a 304 only
      # ever means the body is byte-for-byte the same, whatever the code.
      def index
        # Raw query values, not `permit`: permit silently drops an array sent
        # where one value is expected, while SearchQuery type-checks every
        # value and answers 422. Nothing here is mass-assigned to a model.
        search_params = request.query_parameters.slice(*SEARCH_PARAMS)
        result = Properties::SearchQuery.new(search_params, user: current_user).call

        render_page PropertyResource.new(result.records), result.meta
      end
    end
  end
end
