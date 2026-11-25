# Specs assume an empty database: each example builds its own rows inside a
# transaction that is rolled back. Rows left behind (for example from seeding
# the test database) would skew every count, so fail fast with the fix.
RSpec.configure do |config|
  config.before(:suite) do
    leftovers = [ User, Property, PropertyEvent, WatchlistItem ].select(&:exists?)
    next if leftovers.empty?

    abort "The test database already has #{leftovers.map(&:name).join(', ')} rows. " \
          "Reset it with: RAILS_ENV=test bin/rails db:schema:load"
  end
end
