require "ipaddr"

# The client IP used to key rate limits.
#
# Rack's `req.ip` (and Rails' `remote_ip`) trust X-Forwarded-For whenever the
# peer is a private or loopback address, so a client talking to the app
# through a dev proxy or a Docker network could send a fresh fake IP on every
# request and never be throttled. Here nothing is trusted unless it is listed
# in TRUSTED_PROXIES (comma-separated IPs/CIDRs of the load balancers in front
# of the app). With no proxies listed, the peer address is the client.
module ClientIp
  IPV4_WITH_PORT = /\A(\d{1,3}(?:\.\d{1,3}){3}):\d+\z/
  BRACKETED_IPV6 = /\A\[([^\]]+)\](?::\d+)?\z/

  module_function

  def call(env, trusted_proxies: Rails.configuration.x.trusted_proxies)
    remote_addr = env["REMOTE_ADDR"].to_s
    return remote_addr unless trusted?(remote_addr, trusted_proxies)

    # Each trusted proxy appends the address it received the request from, so
    # walk right to left and stop at the first hop we don't trust.
    forwarded = env["HTTP_X_FORWARDED_FOR"].to_s.split(",").map { |entry| strip_port(entry.strip) }.reject(&:empty?)
    forwarded.reverse.find { |ip| !trusted?(ip, trusted_proxies) } || remote_addr
  end

  # Some proxies append "ip:port" ("[ipv6]:port"). Without this, every
  # connection from one client would get its own rate-limit bucket.
  def strip_port(entry)
    entry[BRACKETED_IPV6, 1] || entry[IPV4_WITH_PORT, 1] || entry
  end

  def trusted?(ip, trusted_proxies)
    addr = IPAddr.new(ip)
    trusted_proxies.any? { |proxy| proxy.include?(addr) }
  rescue IPAddr::Error
    false
  end

  # Raises at boot on a bad entry, naming the variable and the value.
  def parse(list)
    list.to_s.split(",").map(&:strip).reject(&:empty?).map do |cidr|
      IPAddr.new(cidr)
    rescue IPAddr::Error => e
      raise ArgumentError, "TRUSTED_PROXIES has an invalid entry #{cidr.inspect} (#{e.message})"
    end
  end
end
