require "rails_helper"

RSpec.describe WatchlistItem, type: :model do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:property) }

  it "allows a property only once per user (unique index)" do
    item = described_class.create!(user: create(:user), property: create(:property))
    dup = described_class.new(user: item.user, property: item.property)
    expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "goes away with its property or user (FK cascade)" do
    item = described_class.create!(user: create(:user), property: create(:property))
    item.property.delete
    expect(described_class.exists?(item.id)).to be(false)

    item = described_class.create!(user: create(:user), property: create(:property))
    item.user.delete
    expect(described_class.exists?(item.id)).to be(false)
  end
end
