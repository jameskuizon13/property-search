# One token that changes whenever any property changes. Search keys its cached
# counts on it, so a single bump makes every cached count miss at once, with
# no need to know which searches a change affects.
#
# Bumped by Property's after_commit (create, update, destroy) and by the seed.
# Writes that skip callbacks (update_all, insert_all, delete) don't bump it;
# nothing in the app uses them on properties outside the seed.
module SearchCache
  KEY = "search_cache_version".freeze
  # If Redis drops a bump (it was down), the old token comes back. Counts
  # expire after 60 s on their own anyway; the TTL keeps the key itself from
  # living forever.
  TTL = 15.minutes

  module_function

  def version
    Rails.cache.fetch(KEY, expires_in: TTL) { SecureRandom.hex(8) }
  end

  def bump!
    return if Rails.cache.write(KEY, SecureRandom.hex(8), expires_in: TTL)

    Rails.error.report(RuntimeError.new("Could not bump #{KEY}"), handled: true, context: { cache: Rails.cache.class.name })
  end
end
