require "rails_helper"
require Rails.root.join("db/seeds/property_generator")

RSpec.describe PropertyGenerator do
  let(:now) { Time.zone.parse("2026-11-25 12:00:00") }

  it "inserts valid properties across all 8 states" do
    expect(described_class.new(count: 400, now:).call).to eq(400)

    expect(Property.count).to eq(400)
    expect(Property.distinct.pluck(:state)).to match_array(Property::STATES)
    expect(Property.find_each.reject(&:valid?)).to be_empty
  end

  it "writes one status change for each listing no longer for sale" do
    described_class.new(count: 400, now:).call

    no_longer_for_sale = Property.where.not(status: "for_sale")
    status_changes = PropertyEvent.status_changed
    expect(status_changes.pluck(:property_id)).to match_array(no_longer_for_sale.ids)
    status_changes.includes(:property).find_each do |event|
      expect(event).to have_attributes(kind: "status_changed", from_value: "for_sale", to_value: event.property.status)
      expect(event.created_at).to be_between(event.property.listed_at, now)
    end
  end

  it "gives about one in five priced listings a price change or two that end at today's price" do
    described_class.new(count: 1_000, now:).call

    priced = Property.where.not(price_cents: nil)
    changed = Property.where(id: PropertyEvent.price_changed.select(:property_id))
    expect(changed.where(price_cents: nil)).to be_empty
    expect(changed.count).to be_between(priced.count * 0.12, priced.count * 0.28)

    changed.includes(:property_events).find_each do |property|
      events = property.property_events.sort_by { [ _1.created_at, _1.id ] }
      prices = events.select(&:price_changed?)
      expect(prices.size).to be_between(1, 2)
      expect(prices.last.to_value.to_i).to eq(property.price_cents)
      prices.each_cons(2) { |older, newer| expect(newer.from_value).to eq(older.to_value) }
      prices.each { |event| expect((event.from_value.to_i - event.to_value.to_i) % 500_000).to eq(0) }
      expect(events.first.created_at).to be > property.listed_at
      expect(events.map(&:created_at)).to eq(events.map(&:created_at).sort)
      expect(events.last.created_at).to be <= now
      # A status change comes after the price changes.
      expect(events.map(&:kind).drop_while { _1 == "price_changed" }).to all(eq("status_changed"))
    end
    drops = PropertyEvent.price_changed.where("from_value::bigint > to_value::bigint").count
    expect(drops).to be > PropertyEvent.price_changed.count / 2
  end

  it "includes withheld prices, under-offer, sold and withdrawn listings, and ties" do
    described_class.new(count: 1_000, now:).call

    expect(Property.where(price_cents: nil).where.not(price_display: nil).count).to be_between(50, 150)
    expect(Property.where(status: "under_offer").count).to be_between(100, 200)
    expect(Property.where(status: %w[sold withdrawn]).count).to be_positive
    expect(Property.group(:listed_at).having("count(*) > 1").count).not_to be_empty
    expect(Property.where.not(price_cents: nil).group(:price_cents).having("count(*) > 1").count).not_to be_empty
    # Rows that look equal in JSON (same millisecond) but differ in microseconds.
    same_millisecond = Property.group("date_trunc('milliseconds', listed_at)")
                               .having("count(DISTINCT listed_at) > 1").count
    expect(same_millisecond).not_to be_empty
  end

  it "gives every listing a photo that exists in the web app, and a write-up" do
    described_class.new(count: 300, now:).call
    photos = Rails.root.join("../web/public")
    skip "web/ isn't mounted here (the api container has only api/)" unless photos.directory?

    expect(Property.where(image_url: nil).or(Property.where(description: [ nil, "" ]))).to be_empty
    expect(Property.distinct.pluck(:image_url).reject { photos.join(_1.delete_prefix("/")).file? }).to be_empty
    expect(Property.where(property_type: "land").pluck(:image_url)).to all(match(%r{/land-\d+\.webp\z}))
  end

  it "never writes a feature the listing can't have" do
    described_class.new(count: 1_000, now:).call

    expect(Property.where(bathrooms: 0..1).where("description LIKE '%ensuite%'")).to be_empty
    small_or_no_land = Property.where(land_size_sqm: nil).or(Property.where(land_size_sqm: ...200))
    expect(small_or_no_land.where("description LIKE '%backyard%'")).to be_empty
    not_for_sale = Property.where.not(status: "for_sale")
    expect(not_for_sale.where("description LIKE '%won''t last%' OR description LIKE '%Inspection%'")).to be_empty
    expect(Property.where("description LIKE '%private inspection%'")).to be_empty
    land = Property.where(property_type: "land")
    expect(land.where("description LIKE '%light-filled%' OR description LIKE '%next owners%'")).to be_empty
  end

  it "gives every listing an agent at its state's agency, and a gallery that fits its rooms" do
    described_class.new(count: 400, now:).call

    Property.includes(:agent, :photos).find_each do |property|
      expect(property.agent.agency).to eq(ListingExtras::AGENCIES.fetch(property.state))
      captions = property.photos.map(&:caption)
      urls = [ property.image_url, *property.photos.map(&:url) ]
      expect(urls).to eq(urls.uniq)
      expect(captions).not_to include("Bedroom") if property.bedrooms.zero?
      expect(captions).not_to include("Bathroom") if property.bathrooms.zero?
      expect(captions).not_to include("Backyard") if property.land_size_sqm.to_i < 200
      expect(captions).to all(eq("The land")) if property.property_type == "land"
    end
    expect(PropertyPhoto.distinct.pluck(:url).reject { Rails.root.join("../web/public", _1.delete_prefix("/")).file? })
      .to be_empty
  end

  it "gives some listings for sale open homes in the next three weeks, and no others" do
    described_class.new(count: 400, now:).call

    expect(Inspection.joins(:property).where.not(properties: { status: "for_sale" })).to be_empty
    expect(Inspection.count).to be_between(100, 600)
    expect(Inspection.where(starts_at: ..now).or(Inspection.where(starts_at: (now + 22.days)..))).to be_empty
    expect(Inspection.where("ends_at - starts_at <> interval '30 minutes'")).to be_empty
  end

  it "is deterministic for the same random seed, events included" do
    snapshot = lambda do
      [
        Property.order(:id).pluck(:street_address, :suburb, :price_cents, :listed_at, :image_url, :description),
        PropertyEvent.joins(:property).order("properties.id").pluck("properties.street_address", :to_value, :created_at),
        PropertyPhoto.joins(:property).order("properties.id", :position).pluck(:url),
        Inspection.joins(:property).order("properties.id", :starts_at).pluck(:starts_at),
        Property.joins(:agent).order(:id).pluck("agents.name")
      ]
    end
    described_class.new(count: 60, now:).call
    first = snapshot.call
    Property.delete_all # events go with them (FK cascade)
    described_class.new(count: 60, now:).call

    expect(first.last).not_to be_empty
    expect(snapshot.call).to eq(first)
  end
end
