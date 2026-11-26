module Api
  module V1
    class PropertiesController < BaseController
      SEARCH_PARAMS = %w[
        q minPrice maxPrice minBedrooms propertyTypes excludeUnderOffer excludePriceWithheld sort cursor limit
      ].freeze
      # The page shows recent changes, not a full audit trail.
      HISTORY_LIMIT = 20
      # Open homes in the next few weeks; a listing rarely has more.
      INSPECTION_LIMIT = 6

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

      # GET /api/v1/properties/:id
      # Public, like search, and not limited to active listings: a watched
      # property that sold still opens. Signing in only adds `watched`.
      def show
        property = Property.includes(:agent, :photos).find(property_id(params[:id]))
        # One extra row says whether older changes were left out.
        history = property.property_events.order(created_at: :desc, id: :desc).limit(HISTORY_LIMIT + 1).to_a
        history_complete = history.size <= HISTORY_LIMIT
        watched = current_user ? current_user.watchlist_items.exists?(property_id: property.id) : false

        # Only a listing for sale holds open homes; one that went under offer or
        # sold keeps its rows, but they're no longer an invitation.
        inspections = property.for_sale? ? property.inspections.upcoming.limit(INSPECTION_LIMIT).to_a : []

        resource = PropertyDetailResource.new(
          property, params: { watched:, history: history.first(HISTORY_LIMIT), history_complete:, inspections: }
        )
        render json: { data: resource.to_h }
      end
    end
  end
end
