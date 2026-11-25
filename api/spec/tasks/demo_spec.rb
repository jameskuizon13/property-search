require "rails_helper"
require "rake"

RSpec.describe "demo rake tasks" do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("demo:change_property") }

  def run(name, *args)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*args)
  end

  let(:demo) { create(:user, email: "demo@example.com") }
  let!(:property) { create(:property, price_cents: 85_000_000, price_display: "$850,000", status: "for_sale") }

  describe "demo:change_property" do
    it "sets a new price in whole dollars, with its display string" do
      expect { run("demo:change_property", property.id.to_s, "price=820000") }.to output(/\$850,000 → \$820,000/).to_stdout
      expect(property.reload).to have_attributes(price_cents: 82_000_000, price_display: "$820,000")
      expect(property.property_events.pluck(:kind)).to eq([ "price_changed" ])
    end

    it "withholds the price" do
      expect { run("demo:change_property", property.id.to_s, "price=withheld") }.to output(/withheld/).to_stdout
      expect(property.reload).to have_attributes(price_cents: nil, price_display: "Contact agent")
    end

    it "changes the status and broadcasts to watchers" do
      create(:watchlist_item, user: demo, property:)
      expect { run("demo:change_property", property.id.to_s, "status=sold") }
        .to have_broadcasted_to(demo).from_channel(WatchlistChannel)
        .and output(/for_sale → sold \(1 watcher\)/).to_stdout
      expect(property.reload.status).to eq("sold")
    end

    it "says so when nothing changes" do
      expect { run("demo:change_property", property.id.to_s, "status=for_sale") }.to output(/nothing to send/).to_stdout
    end

    {
      "an unknown id" => [ "0", "status=sold" ],
      "a non-numeric id" => [ "12abc", "status=sold" ],
      "an unknown status" => [ :id, "status=auctioned" ],
      "a non-numeric price" => [ :id, "price=820k" ],
      "a negative price" => [ :id, "price=-5" ],
      "a price under $1,000" => [ :id, "price=1" ],
      "a price over $1 billion" => [ :id, "price=1000000001" ],
      "no change" => [ :id, nil ],
      "an unknown attribute" => [ :id, "bedrooms=4" ]
    }.each do |label, (id, change)|
      it "exits with usage for #{label}, changing nothing" do
        id = property.id.to_s if id == :id
        expect { run("demo:change_property", id, change) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
          .and output(/Usage:/).to_stderr
        expect(property.reload).to have_attributes(price_cents: 85_000_000, status: "for_sale")
      end
    end
  end

  it "rejects extra arguments" do
    expect { run("demo:change_property", property.id.to_s, "price=820000", "status=sold") }
      .to raise_error(SystemExit).and output(/Too many arguments/).to_stderr
    expect(property.reload.price_cents).to eq(85_000_000)
  end

  describe "demo:simulate_changes" do
    it "changes only watched properties, one save each" do
      watched = create(:property, price_cents: nil, price_display: "Contact agent")
      create(:watchlist_item, user: demo, property: watched)
      create(:watchlist_item, user: demo, property:)

      expect { run("demo:simulate_changes") }.to output(/#{watched.id}.*\n.*#{property.id}|#{property.id}.*\n.*#{watched.id}/).to_stdout
      expect(PropertyEvent.distinct.pluck(:property_id)).to contain_exactly(watched.id, property.id)
      expect(watched.reload.status).to eq("under_offer") # a withheld price always takes the status step
    end

    it "always moves a price by at least one $5,000 step" do
      cheap = create(:property, price_cents: 5_000_000, price_display: "$50,000")
      create(:watchlist_item, user: demo, property: cheap)
      20.times { expect { run("demo:simulate_changes") }.to output.to_stdout }
      expect(PropertyEvent.where(property: cheap).count).to eq(20)
      expect(cheap.reload.price_cents).to be >= 5_000_000
    end

    it "explains when nothing is watched" do
      expect { run("demo:simulate_changes") }.to output(/No watched properties yet/).to_stdout
    end
  end

  describe "demo:watched" do
    it "lists the demo user's watched properties" do
      create(:watchlist_item, user: demo, property:)
      expect { run("demo:watched") }.to output(/##{property.id}\s+#{property.street_address}/).to_stdout
    end

    it "takes another email" do
      other = create(:user, email: "someone@example.com")
      expect { run("demo:watched", "Someone@Example.com") }.to output(/#{other.email} watches nothing yet/).to_stdout
    end
  end
end
