require "rails_helper"

RSpec.describe Property, type: :model do
  subject(:property) { build(:property) }

  it { is_expected.to be_valid }
  it { is_expected.to have_many(:property_events) }
  it { is_expected.to validate_presence_of(:street_address) }
  it { is_expected.to validate_presence_of(:suburb) }
  it { is_expected.to validate_presence_of(:price_display) }
  it { is_expected.to validate_presence_of(:listed_at) }
  it { is_expected.to validate_inclusion_of(:state).in_array(described_class::STATES) }

  it "uses string-backed enums" do
    expect(described_class.statuses).to eq(
      "for_sale" => "for_sale", "under_offer" => "under_offer", "sold" => "sold", "withdrawn" => "withdrawn"
    )
    expect(described_class.property_types.keys).to eq(described_class::PROPERTY_TYPES.keys)
    expect(described_class.property_types.values).to eq(described_class::PROPERTY_TYPES.keys)
  end

  it "defaults to for sale" do
    expect(described_class.new.status).to eq("for_sale")
  end

  it "reports an unknown status or type as a validation error, not an exception" do
    property.status = "auctioned"
    property.property_type = "castle"
    expect(property).not_to be_valid
    expect(property.errors.attribute_names).to include(:status, :property_type)
  end

  it "requires a 4-digit postcode, keeping a leading zero" do
    expect(build(:property, postcode: "800")).not_to be_valid
    expect(build(:property, postcode: "30650")).not_to be_valid
    expect(build(:property, postcode: "abcd")).not_to be_valid
    expect(build(:property, state: "NT", postcode: "0800")).to be_valid
  end

  it "normalises state and trims text" do
    property = create(:property, state: " vic ", suburb: " Fitzroy ")
    expect(property.reload).to have_attributes(state: "VIC", suburb: "Fitzroy")
  end

  it "allows a withheld price but not a negative one" do
    expect(build(:property, :price_withheld)).to be_valid
    expect(build(:property, price_cents: -1)).not_to be_valid
  end

  it "rejects negative or fractional room counts" do
    expect(build(:property, bedrooms: -1)).not_to be_valid
    expect(build(:property, bathrooms: 1.5)).not_to be_valid
    expect(build(:property, car_spaces: 40_000)).not_to be_valid
  end

  it "caps price and land size, so an oversized value is a validation error, not a 500" do
    expect(build(:property, price_cents: described_class::MAX_PRICE_CENTS)).to be_valid
    expect(build(:property, price_cents: described_class::MAX_PRICE_CENTS + 1)).not_to be_valid
    expect(build(:property, land_size_sqm: 3_000_000_000)).not_to be_valid
  end

  it "rejects out-of-range coordinates" do
    expect(build(:property, latitude: -91)).not_to be_valid
    expect(build(:property, longitude: 181)).not_to be_valid
  end

  describe "database constraints (bad data is blocked even outside Rails)" do
    let(:property) { create(:property) }

    {
      "status" => "auctioned",
      "property_type" => "castle",
      "state" => "XX",
      "postcode" => "123",
      "price_cents" => -1,
      "bedrooms" => -1,
      "land_size_sqm" => -5
    }.each do |column, bad_value|
      it "has a CHECK constraint on #{column}" do
        expect { property.update_columns(column => bad_value) }.to raise_error(ActiveRecord::StatementInvalid, /check/i)
      end
    end

    it "accepts every value the model allows (CHECKs and enums agree)" do
      base = attributes_for(:property).merge(listed_at: Time.current)
      rows = Property::PROPERTY_TYPES.keys.map { |type| base.merge(property_type: type) } +
             Property::STATUSES.map { |status| base.merge(status:) } +
             Property::STATES.map { |state| base.merge(state:) }

      expect { described_class.insert_all!(rows) }.to change(described_class, :count).by(rows.size)
    end

    it "requires the NOT NULL columns" do
      expect { property.update_columns(price_display: nil) }.to raise_error(ActiveRecord::NotNullViolation)
    end
  end

  describe ".active" do
    it "returns for sale and under offer, never sold or withdrawn" do
      for_sale = create(:property, status: "for_sale")
      under_offer = create(:property, status: "under_offer")
      create(:property, status: "sold")
      create(:property, status: "withdrawn")

      expect(described_class.active).to contain_exactly(for_sale, under_offer)
    end

    it "produces the same predicate as the partial indexes" do
      expect(described_class.active.to_sql).to include(%("properties"."status" IN ('for_sale', 'under_offer')))

      predicates = ActiveRecord::Base.connection.indexes(:properties).filter_map(&:where)
      expect(predicates.size).to eq(3)
      expect(predicates).to all(include("'for_sale'").and(include("'under_offer'")))
    end

    it "lets Postgres use the partial indexes, which it can't without the scope" do
      create_list(:property, 3)
      connection = ActiveRecord::Base.connection
      # A test table is tiny and has no statistics, so only check that index
      # paths are possible (which partial index wins at scale is in the
      # README's EXPLAIN section). SET LOCAL ends with the example's transaction.
      connection.execute("SET LOCAL enable_seqscan = off")
      plan = ->(relation) { connection.select_rows("EXPLAIN #{relation.to_sql}").flatten.join("\n") }
      partial_index = /index_properties_active_on_\w+/
      newest = ->(scope) { scope.order(listed_at: :desc, id: :desc).limit(21) }

      expect(plan.call(newest.call(described_class.active))).to match(partial_index)
      expect(plan.call(described_class.active.where.not(price_cents: nil).order(:price_cents, :id).limit(21)))
        .to match(partial_index)
      expect(plan.call(described_class.active.where(property_type: "villa", bedrooms: 4..))).to match(partial_index)
      # Without Property.active the predicate isn't implied, so no partial index.
      expect(plan.call(newest.call(described_class.all))).not_to match(partial_index)
    end
  end

  describe ".format_price" do
    it "formats whole dollars with thousands separators" do
      expect(described_class.format_price(85_000_000)).to eq("$850,000")
      expect(described_class.format_price(1_250_000_00)).to eq("$1,250,000")
    end
  end

  it "uses optimistic locking" do
    property = create(:property)
    stale = described_class.find(property.id)
    property.update!(price_cents: 80_000_000)

    expect { stale.update!(price_cents: 79_000_000) }.to raise_error(ActiveRecord::StaleObjectError)
  end

  it "deletes its events when deleted (FK cascade)" do
    event = create(:property_event)
    event.property.delete
    expect(PropertyEvent.exists?(event.id)).to be(false)
  end

  describe "change events and notifications" do
    let!(:property) { create(:property, price_cents: 85_000_000, price_display: "$850,000", status: "for_sale") }

    before { allow(PropertyChangeNotifier).to receive(:call) }

    def events = property.property_events.order(:id).pluck(:kind, :from_value, :to_value)

    it "writes one price_changed row with the old and new cents" do
      expect { property.update!(price_cents: 82_000_000, price_display: "$820,000") }
        .to change(PropertyEvent, :count).by(1)
      expect(events).to eq([ [ "price_changed", "85000000", "82000000" ] ])
    end

    it "records a withheld price as nil" do
      property.update!(price_cents: nil, price_display: "Contact agent")
      expect(events).to eq([ [ "price_changed", "85000000", nil ] ])
    end

    it "writes one status_changed row" do
      property.update!(status: "sold")
      expect(events).to eq([ %w[status_changed for_sale sold] ])
    end

    it "writes two rows when price and status change in one save" do
      property.update!(price_cents: 80_000_000, status: "under_offer")
      expect(events.map(&:first)).to contain_exactly("price_changed", "status_changed")
    end

    it "writes nothing and notifies no one when another column changes" do
      expect { property.update!(bedrooms: 5, price_display: "Auction") }.not_to change(PropertyEvent, :count)
      expect(PropertyChangeNotifier).not_to have_received(:call)
    end

    it "keeps neither the change nor an event when the save fails" do
      expect { property.update(price_cents: 82_000_000, postcode: "abc") }.not_to change(PropertyEvent, :count)
      expect(property.reload.price_cents).to eq(85_000_000)
    end

    it "rolls back the change when the event row can't be written" do
      allow(property.property_events).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      expect { property.update!(status: "sold") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(property.reload.status).to eq("for_sale")
    end

    it "notifies watchers only after the transaction commits" do
      Property.transaction do
        property.update!(status: "sold")
        expect(PropertyChangeNotifier).not_to have_received(:call)
      end
      expect(PropertyChangeNotifier).to have_received(:call).with(property).once
    end

    it "notifies no one when the transaction rolls back" do
      Property.transaction do
        property.update!(status: "sold")
        raise ActiveRecord::Rollback
      end
      expect(PropertyChangeNotifier).not_to have_received(:call)
      expect(PropertyEvent.count).to eq(0)
    end

    it "bumps lock_version (the API's version) on every save" do
      expect { property.update!(status: "sold") }.to change { property.reload.lock_version }.by(1)
    end
  end

  it "only accepts the web app's own photo paths as image_url" do
    expect(build(:property, image_url: "/images/properties/house-01.webp")).to be_valid
    expect(build(:property, image_url: "https://evil.example/x.webp")).not_to be_valid
  end
end
