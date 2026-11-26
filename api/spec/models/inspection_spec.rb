require "rails_helper"

RSpec.describe Inspection do
  it "must end after it starts, in the model and in the database" do
    starts_at = 1.day.from_now
    expect(build(:inspection, starts_at:, ends_at: starts_at)).not_to be_valid

    property = create(:property)
    expect {
      described_class.insert_all!([ { property_id: property.id, starts_at:, ends_at: starts_at } ])
    }.to raise_error(ActiveRecord::StatementInvalid, /inspections_ends_after_start/)
  end

  it "counts one still under way as upcoming, soonest first" do
    now = Time.zone.parse("2026-11-26 10:15")
    property = create(:property)
    later = create(:inspection, property:, starts_at: now + 2.days)
    under_way = create(:inspection, property:, starts_at: now - 15.minutes)
    create(:inspection, property:, starts_at: now - 1.day)

    expect(property.inspections.upcoming(now)).to eq([ under_way, later ])
  end
end
