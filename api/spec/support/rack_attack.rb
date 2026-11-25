# rack-attack counts in its own MemoryStore in test; reset it so counts from
# one example never throttle the next.
RSpec.configure do |config|
  config.before { Rack::Attack.cache.store.clear }
end
