# Seeds two demo accounts and SEED_COUNT (default 10,000) properties across
# real suburb/postcode pairs from all 8 states and territories.
#
#   bin/rails db:seed                      # adds what is missing
#   make seed  (bin/rails db:seed:replant) # WIPES every table, then reseeds
#   SEED_COUNT=100000 make seed            # bigger set, for EXPLAIN ANALYZE
#
# Never in production unless asked: the demo accounts have a known password,
# and bin/docker-entrypoint runs db:prepare, which seeds a fresh database.
if Rails.env.production? && ENV["SEED_DEMO_DATA"] != "1"
  puts "Skipping demo seed in production (set SEED_DEMO_DATA=1 to force)."
  return
end

require_relative "seeds/property_generator"

DEMO_PASSWORD = "property-demo-2026".freeze

[
  { email: "demo@example.com", name: "Demo User", role: "user" },
  { email: "admin@example.com", name: "Admin User", role: "admin" }
].each do |attrs|
  user = User.find_or_initialize_by(email: attrs[:email])
  user.update!(name: attrs[:name], role: attrs[:role], password: DEMO_PASSWORD)
end
puts "Demo accounts: demo@example.com (user), admin@example.com (admin); password #{DEMO_PASSWORD}"

if Property.exists?
  puts "Properties already seeded (#{Property.count}). Run `make seed` to wipe and reseed."
else
  count = Integer(ENV.fetch("SEED_COUNT", "10000"))
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  inserted = PropertyGenerator.new(count:).call
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  puts format("Seeded %<inserted>d properties in %<elapsed>.1fs.", inserted:, elapsed:)
end
