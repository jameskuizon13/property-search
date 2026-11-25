require "rails_helper"

RSpec.describe SearchCache do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  it "keeps one version until something bumps it" do
    expect(described_class.version).to eq(described_class.version)
    expect { described_class.bump! }.to(change { described_class.version })
  end

  it "expires the version" do
    version = described_class.version
    travel(described_class::TTL + 1.second)
    expect(described_class.version).not_to eq(version)
  end

  it "is bumped when a property is created, updated or destroyed" do
    property = nil
    expect { property = create(:property) }.to(change { described_class.version })
    expect { property.update!(bedrooms: 4) }.to(change { described_class.version })
    expect { property.destroy! }.to(change { described_class.version })
  end

  it "isn't bumped by a change that rolls back" do
    property = create(:property)
    expect do
      Property.transaction do
        property.update!(bedrooms: 4)
        raise ActiveRecord::Rollback
      end
    end.not_to(change { described_class.version })
  end

  it "isn't bumped by writes that skip callbacks (documented; the seed bumps by hand)" do
    property = create(:property)
    expect { Property.where(id: property.id).update_all(bedrooms: 4) }.not_to(change { described_class.version })
  end

  it "reports a bump that couldn't be written" do
    allow(cache).to receive(:write).and_return(false)
    allow(Rails.error).to receive(:report)
    described_class.bump!
    expect(Rails.error).to have_received(:report).with(an_instance_of(RuntimeError), hash_including(handled: true))
  end
end
