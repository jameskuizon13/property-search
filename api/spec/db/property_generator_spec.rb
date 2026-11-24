require "rails_helper"
require Rails.root.join("db/seeds/property_generator")

RSpec.describe PropertyGenerator do
  let(:now) { Time.zone.parse("2026-11-25 12:00:00") }

  it "inserts valid properties across all 8 states without writing events" do
    expect(described_class.new(count: 400, now:).call).to eq(400)

    expect(Property.count).to eq(400)
    expect(Property.distinct.pluck(:state)).to match_array(Property::STATES)
    expect(Property.find_each.reject(&:valid?)).to be_empty
    expect(PropertyEvent.count).to eq(0)
  end

  it "includes withheld prices, under-offer, sold and withdrawn listings, and ties" do
    described_class.new(count: 1_000, now:).call

    expect(Property.where(price_cents: nil).where.not(price_display: nil).count).to be_between(50, 150)
    expect(Property.where(status: "under_offer").count).to be_between(100, 200)
    expect(Property.where(status: %w[sold withdrawn]).count).to be_positive
    expect(Property.group(:listed_at).having("count(*) > 1").count).not_to be_empty
    expect(Property.where.not(price_cents: nil).group(:price_cents).having("count(*) > 1").count).not_to be_empty
  end

  it "is deterministic for the same random seed" do
    described_class.new(count: 20, now:).call
    first = Property.order(:id).pluck(:street_address, :suburb, :price_cents, :listed_at)
    Property.delete_all
    described_class.new(count: 20, now:).call

    expect(Property.order(:id).pluck(:street_address, :suburb, :price_cents, :listed_at)).to eq(first)
  end
end
