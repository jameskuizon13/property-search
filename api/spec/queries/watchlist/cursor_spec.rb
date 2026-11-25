require "rails_helper"

RSpec.describe Watchlist::Cursor do
  let(:watched_at) { Time.zone.parse("2026-11-20 10:00:00.123456") }

  it "round-trips created_at to the microsecond" do
    decoded = described_class.decode(described_class.encode(watched_at:, id: 42))

    expect(decoded.watched_at).to eq(watched_at)
    expect(decoded.watched_at.usec).to eq(123_456)
    expect(decoded.id).to eq(42)
  end

  it "rejects a forged cursor, a search cursor, and type-confused values" do
    token = described_class.encode(watched_at:, id: 42)
    expect(described_class.decode("#{token}x")).to be_nil

    search_cursor = Properties::Cursor.encode(sort: "newest", record: create(:property))
    expect(described_class.decode(search_cursor)).to be_nil

    [
      { "v" => [ "1; DROP TABLE", 1 ] },
      { "v" => [ 1, 2, 3 ] },
      { "v" => "1,2" },
      [ 1, 2 ]
    ].each do |payload|
      expect(described_class.decode(described_class.verifier.generate(payload))).to be_nil
    end
  end
end
