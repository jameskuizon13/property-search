require "rails_helper"

RSpec.describe PropertyChangeNotifier do
  let(:property) { create(:property, price_cents: 85_000_000, price_display: "$850,000") }
  let(:watcher) { create(:user) }
  let(:other_watcher) { create(:user) }
  let(:bystander) { create(:user) }

  before do
    create(:watchlist_item, user: watcher, property:)
    create(:watchlist_item, user: other_watcher, property:)
    create(:watchlist_item, user: bystander, property: create(:property))
  end

  def change_price
    property.update!(price_cents: 82_000_000, price_display: "$820,000")
  end

  it "broadcasts to every watcher of the property" do
    expect { change_price }
      .to have_broadcasted_to(watcher).from_channel(WatchlistChannel)
      .and have_broadcasted_to(other_watcher).from_channel(WatchlistChannel)
  end

  it "doesn't broadcast to users who don't watch it" do
    expect { change_price }.not_to have_broadcasted_to(bystander).from_channel(WatchlistChannel)
  end

  it "sends the REST shape with the new version, watched: true and the camelCase changes" do
    expect { change_price }.to have_broadcasted_to(watcher).from_channel(WatchlistChannel).with { |message|
      expect(message["type"]).to eq("property.updated")
      expect(message["property"]).to include(
        "id" => property.id, "priceCents" => 82_000_000, "priceDisplay" => "$820,000",
        "version" => property.reload.lock_version, "watched" => true
      )
      expect(message["property"]["version"]).to eq(1)
      expect(message["changes"]).to eq("priceCents" => [ 85_000_000, 82_000_000 ])
    }
  end

  it "includes both changes when price and status change together" do
    expect { property.update!(price_cents: nil, price_display: "Contact agent", status: "sold") }
      .to have_broadcasted_to(watcher).from_channel(WatchlistChannel).with { |message|
        expect(message["changes"]).to eq("priceCents" => [ 85_000_000, nil ], "status" => %w[for_sale sold])
      }
  end

  it "returns how many watchers it notified" do
    change_price
    expect(described_class.call(property)).to eq(2)
  end

  it "reports a broadcast failure instead of raising, keeping the saved change" do
    allow(WatchlistChannel).to receive(:broadcast_to).and_raise(Redis::CannotConnectError)
    allow(Rails.error).to receive(:report)

    expect { change_price }.not_to raise_error
    expect(property.reload.price_cents).to eq(82_000_000)
    expect(Rails.error).to have_received(:report).with(an_instance_of(Redis::CannotConnectError), hash_including(handled: true))
  end
end
