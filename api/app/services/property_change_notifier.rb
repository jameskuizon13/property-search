# Tells everyone watching a property that its price or status changed. Called
# by Property's after_update_commit, so only saved changes are broadcast.
#
# Inline, with no job: each broadcast is one Redis publish (~1 ms), and inline
# sends also work from rake tasks and the console, which exit right after. At
# scale this would move into a Solid Queue job with retries.
class PropertyChangeNotifier
  TYPE = "property.updated".freeze

  # Returns how many watchers were notified.
  def self.call(property) = new(property).call

  def initialize(property)
    @property = property
  end

  def call
    notified = 0
    # The change is already committed. If Redis is down, report it rather than
    # turning a saved change into an error for whoever made it; watchers see
    # the new values on their next refetch.
    Rails.error.handle(context: { property_id: @property.id, notifier: self.class.name }) do
      message = payload
      watchers.find_each do |user|
        WatchlistChannel.broadcast_to(user, message)
        notified += 1
      end
    end
    notified
  end

  private

  # One query per 1,000 watchers, through the watchlist_items(property_id) index.
  def watchers
    User.where(id: WatchlistItem.where(property_id: @property.id).select(:user_id))
  end

  # The same shape as REST, so the client drops it straight into its cache.
  # `watched` is true: only watchers receive it.
  def payload
    {
      type: TYPE,
      property: PropertyResource.new(@property, params: { watched: true }).to_h,
      changes: changes
    }
  end

  def changes
    {}.tap do |changes|
      changes[:priceCents] = @property.saved_change_to_price_cents if @property.saved_change_to_price_cents?
      changes[:status] = @property.saved_change_to_status if @property.saved_change_to_status?
    end
  end
end
