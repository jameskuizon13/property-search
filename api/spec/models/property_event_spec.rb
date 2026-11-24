require "rails_helper"

RSpec.describe PropertyEvent, type: :model do
  it { is_expected.to belong_to(:property) }

  it "has exactly two string-backed kinds" do
    expect(described_class.kinds).to eq("price_changed" => "price_changed", "status_changed" => "status_changed")
  end

  it "reports an unknown kind as a validation error" do
    event = build(:property_event, kind: "renamed")
    expect(event).not_to be_valid
    expect(event.errors[:kind]).to be_present
  end

  it "has a CHECK constraint on kind" do
    event = create(:property_event)
    expect { event.update_columns(kind: "renamed") }.to raise_error(ActiveRecord::StatementInvalid, /check/i)
  end

  it "requires an existing property (FK)" do
    expect { build(:property_event, property_id: 0).save!(validate: false) }
      .to raise_error(ActiveRecord::InvalidForeignKey)
  end
end
