require "rails_helper"

RSpec.describe ClientIp do
  def ip(remote, xff = nil, trusted: "")
    env = { "REMOTE_ADDR" => remote }
    env["HTTP_X_FORWARDED_FOR"] = xff if xff
    described_class.call(env, trusted_proxies: described_class.parse(trusted))
  end

  it "uses the peer address when no proxies are trusted, whatever X-Forwarded-For says" do
    expect(ip("127.0.0.1", "198.51.100.7")).to eq("127.0.0.1")
    expect(ip("172.18.0.3", "198.51.100.7")).to eq("172.18.0.3")
  end

  it "takes the nearest untrusted hop behind trusted proxies" do
    expect(ip("10.0.0.5", "203.0.113.9, 198.51.100.7", trusted: "10.0.0.0/8")).to eq("198.51.100.7")
    expect(ip("10.0.0.5", "198.51.100.7, 10.0.0.4", trusted: "10.0.0.0/8")).to eq("198.51.100.7")
  end

  it "falls back to the peer when every hop is trusted or the header is missing" do
    expect(ip("10.0.0.5", nil, trusted: "10.0.0.0/8")).to eq("10.0.0.5")
    expect(ip("10.0.0.5", "10.0.0.4", trusted: "10.0.0.0/8")).to eq("10.0.0.5")
  end

  it "handles IPv6 peers and entries" do
    expect(ip("::1", "198.51.100.7")).to eq("::1")
    expect(ip("2001:db8::5", "2001:db8:1::9", trusted: "2001:db8::/64")).to eq("2001:db8:1::9")
  end

  it "does not treat an IPv4-mapped IPv6 address as its IPv4 proxy" do
    expect(ip("::ffff:127.0.0.1", "198.51.100.7", trusted: "127.0.0.1/32")).to eq("::ffff:127.0.0.1")
  end

  it "strips ports so one client keeps one bucket" do
    expect(ip("10.0.0.5", "198.51.100.7:51234", trusted: "10.0.0.0/8")).to eq("198.51.100.7")
    expect(ip("10.0.0.5", "[2001:db8::1]:443", trusted: "10.0.0.0/8")).to eq("2001:db8::1")
    expect(ip("10.0.0.5", "203.0.113.9, 10.0.0.4:8080", trusted: "10.0.0.0/8")).to eq("203.0.113.9")
  end

  it "fails loudly on a bad TRUSTED_PROXIES entry, naming it" do
    [ "not-an-ip", "localhost", "10.0.0.1:8080", "10.0.0.0/33" ].each do |bad|
      expect { described_class.parse("10.0.0.0/8, #{bad}") }
        .to raise_error(ArgumentError, /TRUSTED_PROXIES has an invalid entry #{Regexp.escape(bad.inspect)}/)
    end
  end

  it "treats garbage entries as untrusted" do
    expect(ip("10.0.0.5", "not-an-ip", trusted: "10.0.0.0/8")).to eq("not-an-ip")
  end
end
