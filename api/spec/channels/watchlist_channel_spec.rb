require "rails_helper"

RSpec.describe WatchlistChannel, type: :channel do
  let(:user) { create(:user) }

  it "streams the signed-in user's own updates" do
    stub_connection current_user: user
    subscribe
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(user)
  end

  it "ignores subscription params: there is no way to ask for another user's stream" do
    other = create(:user)
    stub_connection current_user: user
    subscribe(user_id: other.id, id: other.id)
    expect(subscription).to have_stream_for(user)
    expect(subscription).not_to have_stream_for(other)
  end

  it "exposes no actions, so a client can't re-run subscribed" do
    expect(described_class.action_methods).to be_empty
  end

  it "rejects a subscription without a user" do
    stub_connection current_user: nil
    subscribe
    expect(subscription).to be_rejected
  end
end
