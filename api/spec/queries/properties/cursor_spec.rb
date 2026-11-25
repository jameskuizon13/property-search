require "rails_helper"

RSpec.describe Properties::Cursor do
  let(:property) { create(:property, listed_at: Time.zone.parse("2026-11-20 10:00:00.123456"), price_cents: 85_000_000) }

  it "round-trips listed_at to the microsecond" do
    token = described_class.encode(sort: "newest", record: property)
    decoded = described_class.decode(token, sort: "newest")

    expect(decoded.value).to eq(property.reload.listed_at)
    expect(decoded.value.usec).to eq(123_456)
    expect(decoded.id).to eq(property.id)
  end

  it "stores price sorts by price_cents" do
    token = described_class.encode(sort: "price_desc", record: property)
    expect(described_class.decode(token, sort: "price_desc")).to have_attributes(value: 85_000_000, id: property.id)
  end

  it "rejects a cursor for another sort, a forged one, and type-confused values" do
    token = described_class.encode(sort: "newest", record: property)
    expect(described_class.decode(token, sort: "price_asc")).to be_nil
    expect(described_class.decode("#{token}x", sort: "newest")).to be_nil

    wrong_types = described_class.verifier.generate({ "s" => "newest", "v" => [ "1; DROP TABLE", 1 ] })
    expect(described_class.decode(wrong_types, sort: "newest")).to be_nil
    wrong_size = described_class.verifier.generate({ "s" => "newest", "v" => [ 1, 2, 3 ] })
    expect(described_class.decode(wrong_size, sort: "newest")).to be_nil
    not_a_hash = described_class.verifier.generate([ 1, 2 ])
    expect(described_class.decode(not_a_hash, sort: "newest")).to be_nil
  end
end
