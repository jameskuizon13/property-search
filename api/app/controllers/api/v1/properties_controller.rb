module Api
  module V1
    class PropertiesController < BaseController
      SEARCH_PARAMS = %w[
        q minPrice maxPrice minBedrooms propertyTypes excludeUnderOffer excludePriceWithheld sort cursor limit
      ].freeze
      # Bump when the response shape changes, so browsers can't keep a body
      # cached under the old shape. A deploy revision (GIT_SHA) does it too.
      ETAG_SCHEMA = 1

      # GET /api/v1/properties
      # Public; signing in only adds the per-user `watched` flag.
      def index
        # Raw query values, not `permit`: permit silently drops an array sent
        # where one value is expected, while SearchQuery type-checks every
        # value and answers 422. Nothing here is mass-assigned to a model.
        search_params = request.query_parameters.slice(*SEARCH_PARAMS)
        query = Properties::SearchQuery.new(search_params, user: current_user)
        query.validate! # a bad request is a 422, never a 304

        # Answer 304 before running the search when nothing it depends on has
        # changed: the properties (SearchCache), the user and their watchlist
        # (`watched` flags), and the normalised params.
        return unless stale?(etag: [ ETAG_SCHEMA, ENV["GIT_SHA"], SearchCache.version, current_user&.id,
                                     watchlist_fingerprint, query.cache_key_parts ])

        result = query.call
        render_page PropertyResource.new(result.records), result.meta
      end

      private

      # Changes on every watch and unwatch: unwatching lowers the count, and
      # watching adds a row with a higher id (ids come from a sequence and are
      # never reused, unlike timestamps from the app's clock). One index-only
      # query on (user_id, ...).
      def watchlist_fingerprint
        current_user&.watchlist_items&.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(watchlist_items.id)"))
      end
    end
  end
end
