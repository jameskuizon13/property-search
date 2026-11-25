require "rails_helper"

# Guards the N+1 safety net itself: if Bullet stopped raising, every request
# spec would silently stop catching N+1 queries.
RSpec.describe "Bullet in the test suite" do
  it "is enabled" do
    expect(Bullet.enable?).to be(true)
  end

  it "fails on an N+1 query" do
    create_list(:property_event, 2)

    expect {
      Bullet.profile { PropertyEvent.all.each(&:property) }
    }.to raise_error(Bullet::Notification::UnoptimizedQueryError)
  end
end
