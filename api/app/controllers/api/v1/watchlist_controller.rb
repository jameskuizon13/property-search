module Api
  module V1
    # The signed-in user's watchlist. Every lookup goes through
    # current_user.watchlist_items (or Watchlist::ListQuery, scoped the same
    # way), so one user can never read or change another's (no IDOR). The
    # client never needs a watchlist-item id: PUT and DELETE are keyed on the
    # property, which makes the toggle idempotent.
    class WatchlistController < BaseController
      PROPERTY_ID = /\A[1-9]\d{0,18}\z/

      before_action :authenticate!

      # The property was deleted between the lookup and the insert.
      rescue_from ActiveRecord::InvalidForeignKey do
        render_error :not_found, "not_found", "Property not found"
      end

      # GET /api/v1/watchlist
      # Most recently added first. Not limited to active listings, so a
      # watched property that sells stays here with its new status.
      def index
        result = Watchlist::ListQuery.new(request.query_parameters.slice("cursor", "limit"), user: current_user).call
        render_page PropertyResource.new(result.records, params: { watched: true }), result.meta
      end

      # PUT /api/v1/watchlist/:property_id
      # 201 when added, 200 when it was already there. create_or_find_by!
      # inserts first and falls back to the existing row on the unique
      # index, so two PUTs racing each other both succeed.
      def update
        property = Property.find(property_id)
        item = current_user.watchlist_items.create_or_find_by!(property:)
        render json: { data: PropertyResource.new(property, params: { watched: true }).to_h },
               status: item.previously_new_record? ? :created : :ok
      end

      # DELETE /api/v1/watchlist/:property_id
      # 204 whether or not it was watched, or even exists.
      def destroy
        current_user.watchlist_items.where(property_id:).delete_all
        head :no_content
      end

      private

      # Only plain positive integers that fit a bigint. Without this, "12abc"
      # would be cast to 12 and act on another property.
      def property_id
        id = params[:property_id]
        raise ActiveRecord::RecordNotFound.new("Property not found", "Property") unless PROPERTY_ID.match?(id)

        id.to_i
      end
    end
  end
end
