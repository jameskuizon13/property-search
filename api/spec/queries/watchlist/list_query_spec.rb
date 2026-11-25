require "rails_helper"

RSpec.describe Watchlist::ListQuery do
  let(:user) { create(:user) }

  def watch(property, at:)
    WatchlistItem.create!(user:, property:, created_at: at)
  end

  it "uses the (user_id, created_at, id) index for a later page" do
    sql = described_class.new({ "cursor" => Watchlist::Cursor.encode(watched_at: Time.current, id: 1) }, user:)
                         .relation.to_sql
    expect(sql).to include(%("watchlist_items"."user_id" = #{user.id}))
    expect(sql).to include("(watchlist_items.created_at, watchlist_items.id) < (")
    expect(sql).to include(%(ORDER BY "watchlist_items"."created_at" DESC, "watchlist_items"."id" DESC))
  end

  it "keeps rows added in the same microsecond in a stable order (ties broken by id)" do
    at = Time.zone.parse("2026-11-20 10:00:00.123456")
    items = Array.new(3) { watch(create(:property), at:) }

    first = described_class.new({ "limit" => "2" }, user:).call
    second = described_class.new({ "limit" => "2", "cursor" => first.meta[:next_cursor] }, user:).call

    expect((first.records + second.records).map(&:watchlist_item_id)).to eq(items.map(&:id).reverse)
  end

  it "raises a validation error for a bad limit or cursor" do
    expect { described_class.new({ "limit" => "0" }, user:).call }.to raise_error(ActiveModel::ValidationError)
    expect { described_class.new({ "cursor" => "nope" }, user:).call }.to raise_error(ActiveModel::ValidationError)
  end
end
