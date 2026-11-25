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

  it "writes one status change for each listing no longer for sale, and nothing else" do
    described_class.new(count: 400, now:).call

    no_longer_for_sale = Property.where.not(status: "for_sale")
    expect(PropertyEvent.count).to eq(no_longer_for_sale.count)
    expect(PropertyEvent.pluck(:property_id)).to match_array(no_longer_for_sale.ids)
    PropertyEvent.includes(:property).find_each do |event|
      expect(event).to have_attributes(kind: "status_changed", from_value: "for_sale", to_value: event.property.status)
      expect(event.created_at).to be_between(event.property.listed_at, now)
    end
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
  end

  it "is deterministic for the same random seed, events included" do
    snapshot = lambda do
      [
        Property.order(:id).pluck(:street_address, :suburb, :price_cents, :listed_at, :image_url, :description),
        PropertyEvent.joins(:property).order("properties.id").pluck("properties.street_address", :to_value, :created_at)
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
