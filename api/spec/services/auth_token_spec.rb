require "rails_helper"

RSpec.describe AuthToken do
  let(:user) { create(:user) }

  it "round-trips a user id" do
    expect(described_class.decode(described_class.encode(user))).to eq(user.id)
  end

  it "expires after 24 hours" do
    token = described_class.encode(user)
    travel_to(24.hours.from_now + 1.second) do
      expect(described_class.decode(token)).to be_nil
    end
  end

  it "is still valid just before 24 hours" do
    token = described_class.encode(user)
    travel_to(24.hours.from_now - 1.minute) do
      expect(described_class.decode(token)).to eq(user.id)
    end
  end

  it "rejects a tampered token" do
    header, payload, signature = described_class.encode(user).split(".")
    forged = Base64.urlsafe_encode64({ sub: "999", iat: Time.now.to_i, exp: 1.hour.from_now.to_i }.to_json, padding: false)
    expect(described_class.decode([ header, forged, signature ].join("."))).to be_nil
    expect(described_class.decode([ header, payload, signature.reverse ].join("."))).to be_nil
  end

  it "rejects an unsigned alg: none token" do
    token = JWT.encode({ sub: user.id.to_s, iat: Time.now.to_i, exp: 1.hour.from_now.to_i }, nil, "none")
    expect(described_class.decode(token)).to be_nil
  end

  it "rejects a token signed with a different algorithm" do
    token = JWT.encode({ sub: user.id.to_s, iat: Time.now.to_i, exp: 1.hour.from_now.to_i }, described_class.secret, "HS512")
    expect(described_class.decode(token)).to be_nil
  end

  it "rejects a token signed with another secret" do
    token = JWT.encode({ sub: user.id.to_s, iat: Time.now.to_i, exp: 1.hour.from_now.to_i }, "x" * 64, "HS256")
    expect(described_class.decode(token)).to be_nil
  end

  it "rejects a token without an exp claim" do
    token = JWT.encode({ sub: user.id.to_s, iat: Time.now.to_i }, described_class.secret, "HS256")
    expect(described_class.decode(token)).to be_nil
  end

  it "rejects a token without a sub claim" do
    token = JWT.encode({ iat: Time.now.to_i, exp: 1.hour.from_now.to_i }, described_class.secret, "HS256")
    expect(described_class.decode(token)).to be_nil
  end

  it "rejects a token without an iat claim" do
    token = JWT.encode({ sub: user.id.to_s, exp: 1.hour.from_now.to_i }, described_class.secret, "HS256")
    expect(described_class.decode(token)).to be_nil
  end

  it "rejects a token that lives longer than 24 hours, even when correctly signed" do
    token = JWT.encode({ sub: user.id.to_s, iat: Time.now.to_i, exp: 10.years.from_now.to_i }, described_class.secret, "HS256")
    expect(described_class.decode(token)).to be_nil
  end

  [ "0x#{1}", "01", " 1 ", "1_0", "-1", "0", "1.0" ].each do |sub|
    it "rejects the non-canonical sub #{sub.inspect}" do
      token = JWT.encode({ sub:, iat: Time.now.to_i, exp: 1.hour.from_now.to_i }, described_class.secret, "HS256")
      expect(described_class.decode(token)).to be_nil
    end
  end

  def token_with(claims)
    JWT.encode({ sub: user.id.to_s }.merge(claims), described_class.secret, "HS256")
  end

  # Correctly signed HS256 token with any payload; ruby-jwt refuses to
  # encode some of the malformed claims we want to test.
  def raw_token(payload)
    b64 = ->(data) { Base64.urlsafe_encode64(data, padding: false) }
    signing_input = "#{b64.(JSON.generate(alg: "HS256", typ: "JWT"))}.#{b64.(JSON.generate(payload))}"
    "#{signing_input}.#{b64.(OpenSSL::HMAC.digest("SHA256", described_class.secret, signing_input))}"
  end

  it "accepts a token that lives exactly 24 hours" do
    now = Time.now.to_i
    expect(described_class.decode(token_with(iat: now, exp: now + 24.hours.to_i))).to eq(user.id)
  end

  it "rejects a token issued in the future" do
    now = Time.now.to_i
    expect(described_class.decode(token_with(iat: now + 60, exp: now + 3600))).to be_nil
  end

  it "rejects float and string exp/iat claims" do
    now = Time.now.to_i
    expect(described_class.decode(token_with(iat: now, exp: now + 3600.5))).to be_nil
    expect(described_class.decode(token_with(iat: now.to_f, exp: now + 3600))).to be_nil
    expect(described_class.decode(raw_token(sub: user.id.to_s, iat: now.to_s, exp: now + 3600))).to be_nil
    expect(described_class.decode(raw_token(sub: user.id.to_s, iat: now, exp: (now + 3600).to_s))).to be_nil
    # sanity: the hand-signed helper produces tokens we accept when well-formed
    expect(described_class.decode(raw_token(sub: user.id.to_s, iat: now, exp: now + 3600))).to eq(user.id)
  end

  it "rejects an integer sub (we only issue strings)" do
    now = Time.now.to_i
    token = JWT.encode({ sub: user.id, iat: now, exp: now + 3600 }, described_class.secret, "HS256")
    expect(described_class.decode(token)).to be_nil
  end

  it "rejects garbage and blanks" do
    expect(described_class.decode("not.a.jwt")).to be_nil
    expect(described_class.decode("")).to be_nil
    expect(described_class.decode(nil)).to be_nil
  end

  it "returns no user once the user is deleted" do
    token = described_class.encode(user)
    user.destroy!
    expect(described_class.user_from(token)).to be_nil
  end
end
