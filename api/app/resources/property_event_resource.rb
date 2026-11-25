# One entry in a property's price and status history. Prices are stored as
# text (the column holds statuses too), so they go back to integer cents here;
# a withheld price is null, and so is every amount when the caller passes
# hide_prices (the property's price is withheld now).
class PropertyEventResource
  include Alba::Resource

  transform_keys :lower_camel

  attributes :id, :kind, :created_at

  attribute(:from) { |event| event_value(event, event.from_value) }
  attribute(:to) { |event| event_value(event, event.to_value) }

  helper do
    def event_value(event, value)
      return value unless event.price_changed?

      params[:hide_prices] ? nil : value&.to_i
    end
  end
end
