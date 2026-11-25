# Seeds two demo accounts and SEED_COUNT (default 10,000) properties across
# real suburb/postcode pairs from all 8 states and territories.
#
#   bin/rails db:seed                      # adds what is missing
#   make seed  (bin/rails db:seed:replant) # WIPES every table, then reseeds
#   SEED_COUNT=100000 make seed            # bigger set, for EXPLAIN ANALYZE
#
# Never in production unless asked: the demo accounts have a known password,
# and bin/docker-entrypoint runs db:prepare, which seeds a fresh database.
# Never in test: specs build their own data inside transactions, and seed
# rows would leak into every count. (db:prepare seeds a freshly created
# database, which is how this used to happen in CI.)
if Rails.env.test?
  puts "Skipping seed in the test environment."
  return
end

if Rails.env.production? && ENV["SEED_DEMO_DATA"] != "1"
  puts "Skipping demo seed in production (set SEED_DEMO_DATA=1 to force)."
  return
end

require_relative "seeds/property_generator"

# Published in the README for local use. Forcing the seed in production
# requires choosing a password instead.
DEMO_PASSWORD =
  if Rails.env.production?
    ENV.fetch("SEED_DEMO_PASSWORD") { abort "Set SEED_DEMO_PASSWORD to seed demo accounts in production." }
  else
    "property-demo-2026"
  end

[
  { email: "demo@example.com", name: "Demo User", role: "user" },
  { email: "admin@example.com", name: "Admin User", role: "admin" }
].each do |attrs|
  user = User.find_or_initialize_by(email: attrs[:email])
  user.update!(name: attrs[:name], role: attrs[:role], password: DEMO_PASSWORD)
end
puts "Demo accounts: demo@example.com (user), admin@example.com (admin)"
puts "Password: #{DEMO_PASSWORD}" unless Rails.env.production?

if Property.exists?
  puts "Properties already seeded (#{Property.count}). Run `make seed` to wipe and reseed."
else
  count = Integer(ENV.fetch("SEED_COUNT", "10000"))
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  inserted = PropertyGenerator.new(count:).call
  # Extended statistics (see the AddPropertyTypeBedroomsStatistics migration;
  # schema.rb can't record them), then fresh planner statistics, so EXPLAIN
  # reflects the new rows right away instead of waiting for autovacuum.
  connection = ActiveRecord::Base.connection
  connection.execute(<<~SQL)
    CREATE STATISTICS IF NOT EXISTS properties_type_bedrooms_stats (mcv) ON property_type, bedrooms FROM properties
  SQL
  connection.execute("ANALYZE properties")
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  puts format("Seeded %<inserted>d properties in %<elapsed>.1fs.", inserted:, elapsed:)
end

# Replant wipes properties, users and watchlists without callbacks, so cached
# search counts and ETags must be invalidated by hand.
SearchCache.bump!
