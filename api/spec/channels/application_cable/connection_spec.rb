require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user) }

  it "identifies the user from the auth cookie" do
    cookies[AuthToken::COOKIE_NAME] = AuthToken.encode(user)
    connect "/cable"
    expect(connection.current_user).to eq(user)
  end

  it "rejects a connection with no cookie" do
    expect { connect "/cable" }.to have_rejected_connection
  end

  it "rejects an expired token" do
    cookies[AuthToken::COOKIE_NAME] = AuthToken.encode(user, now: 25.hours.ago)
    expect { connect "/cable" }.to have_rejected_connection
  end

  it "rejects a tampered token" do
    cookies[AuthToken::COOKIE_NAME] = AuthToken.encode(user).chop
    expect { connect "/cable" }.to have_rejected_connection
  end

  describe "request origin" do
    def origin_allowed?(origin)
      env = Rack::MockRequest.env_for("/cable", "HTTP_ORIGIN" => origin)
      described_class.new(ActionCable.server, env).send(:allow_request_origin?)
    end

    it "accepts the web app's origin" do
      expect(origin_allowed?(Rails.configuration.x.frontend_origins.first)).to be(true)
    end

    it "rejects a foreign origin (cross-site WebSocket hijacking)" do
      expect(origin_allowed?("https://evil.example")).to be(false)
    end

    it "rejects a handshake with no Origin header" do
      expect(origin_allowed?(nil)).to be(false)
    end
  end
end
