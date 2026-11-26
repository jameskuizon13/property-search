require_relative "listing_extras"

# Builds realistic-looking Australian listings and bulk-inserts them with
# insert_all, so 10k rows take a few seconds. insert_all skips callbacks on
# purpose: seeding must not broadcast anything. The only property_events it
# writes are its own: a status change for each listing no longer for sale,
# and a price change or two for about one in five listings with a price, so
# the property page's history has something to show. Agents, galleries and open homes come
# from ListingExtras.
#
# Deterministic: the same count, random seed and `now` give the same rows.
# The seed passes the current time, so listing dates are relative to when it
# ran, and ids come from the table's sequence, so they change on reseed.
class PropertyGenerator
  SUBURBS_CSV = File.expand_path("suburbs.csv", __dir__)
  BATCH_SIZE = 2_000

  # Rough state medians in whole AUD. Only used to make prices look plausible.
  STATE_BASE_PRICE = {
    "NSW" => 1_100_000, "VIC" => 820_000, "QLD" => 780_000, "WA" => 720_000,
    "SA" => 700_000, "TAS" => 650_000, "ACT" => 900_000, "NT" => 520_000
  }.freeze

  # type => [weight, price multiplier]
  TYPES = {
    "house" => [ 45, 1.0 ], "apartment_unit" => [ 25, 0.55 ], "townhouse" => [ 10, 0.8 ],
    "villa" => [ 4, 0.75 ], "land" => [ 6, 0.45 ], "acreage" => [ 3, 1.3 ], "rural" => [ 2, 1.1 ],
    "block_of_units" => [ 2, 2.2 ], "retirement_living" => [ 3, 0.45 ]
  }.freeze

  STREET_NAMES = %w[
    Smith George King Queen Victoria Albert Elizabeth Church High Station Railway Park Wattle
    Banksia Acacia Bay Beach Ocean Hill Grey Bridge Mill Market Union Pitt Hunter Macquarie
    Flinders Collins Bourke Lonsdale Spencer Swanston Brunswick Gertrude Johnston Rose Lygon
    Charles William Edward Alfred Arthur Albion Waratah Bottlebrush Jacaranda Kurrajong Gum
    Ironbark Hampden Carrington Darling Stirling Hay Murray Wellington Barrack Grote Rundle
  ].freeze
  STREET_SUFFIXES = %w[St St St Rd Rd Ave Pde Cres Ct Dr Pl Tce Lane Way].freeze
  WITHHELD_DISPLAYS = [ "Contact agent", "Contact agent", "Auction", "Price on application" ].freeze

  # Demo photos in web/public/images/properties (credits in CREDITS.md there),
  # served by the web app, so image_url is a path on the web origin.
  PHOTO_DIR = "/images/properties"
  PHOTO_SETS = {
    "house" => 12, "apartment" => 6, "townhouse" => 6, "units" => 2, "land" => 4, "rural" => 5
  }.freeze
  # type => the photo sets that suit it
  TYPE_PHOTOS = {
    "house" => %w[house], "apartment_unit" => %w[apartment], "townhouse" => %w[townhouse],
    "villa" => %w[townhouse house], "land" => %w[land], "acreage" => %w[rural land], "rural" => %w[rural],
    "block_of_units" => %w[units apartment], "retirement_living" => %w[apartment townhouse]
  }.freeze

  TYPE_NOUNS = {
    "house" => "family home", "apartment_unit" => "apartment", "townhouse" => "townhouse", "villa" => "villa",
    "land" => "block of land", "acreage" => "acreage property", "rural" => "rural holding",
    "block_of_units" => "block of units", "retirement_living" => "retirement unit"
  }.freeze
  OPENERS = [
    "Welcome to %<address>s, a %<adjective>s %<noun>s in the heart of %<suburb>s.",
    "Set on a quiet street in %<suburb>s, this %<adjective>s %<noun>s is ready for its next owners.",
    "Opportunity knocks in %<suburb>s with this %<adjective>s %<noun>s."
  ].freeze
  # Only while it's for sale: an under-offer or sold listing saying "won't
  # last" reads as a mistake.
  FOR_SALE_OPENERS = [
    "Positioned close to everything %<suburb>s has to offer, this %<adjective>s %<noun>s won't last."
  ].freeze
  ADJECTIVES = %w[light-filled well-kept spacious stylish charming renovated low-maintenance sun-drenched].freeze
  # Vacant land gets land words, not "light-filled" or "next owners".
  LAND_OPENERS = [
    "Build your dream home on this %<adjective>s block in %<suburb>s.",
    "Welcome to %<address>s, a %<adjective>s block of land in %<suburb>s.",
    "Opportunity knocks in %<suburb>s with this %<adjective>s block of land."
  ].freeze
  LAND_ADJECTIVES = %w[level elevated north-facing generous cleared corner].freeze
  # text => which listings it may describe, so a write-up never contradicts
  # the facts beside it (an ensuite needs two bathrooms, a yard needs land).
  HIGHLIGHTS = {
    "An open-plan kitchen and living area flows out to a covered alfresco area." => ->(_) { true },
    "The kitchen has stone benchtops, a gas cooktop and plenty of storage." => ->(_) { true },
    "Ducted air conditioning keeps it comfortable all year round." => ->(_) { true },
    "Polished timber floors and high ceilings run throughout." => ->(_) { true },
    "The main bedroom has built-in robes and its own ensuite." =>
      ->(rooms) { rooms[:bathrooms] >= 2 && rooms[:bedrooms] >= 1 },
    "Every bedroom has built-in robes." => ->(rooms) { rooms[:bedrooms] >= 2 },
    "A low-maintenance backyard is ready for weekend barbecues." => ->(rooms) { rooms[:land_size_sqm].to_i >= 200 },
    "Solar panels keep the power bills down." => ->(_) { true },
    "Large windows bring in the northern light." => ->(_) { true }
  }.freeze
  LAND_HIGHLIGHTS = [
    "A level, cleared block that is ready to build on.",
    "Water, power and sewer are available at the boundary.",
    "Room for a family home, a shed and a big garden.",
    "Gentle rural views from across the block."
  ].freeze
  CLOSERS = [
    "Walk to local cafes, schools and parks, with public transport close by.",
    "Shops, schools and transport are all a short drive away."
  ].freeze
  # Only while it's for sale. Neither mentions how to inspect, so neither
  # contradicts the open homes listed beside it.
  FOR_SALE_CLOSERS = [
    "Inspection is highly recommended.",
    "Contact the agent for more details."
  ].freeze

  INSERTED_COLUMNS = %w[
    id status listed_at price_cents property_type bedrooms bathrooms land_size_sqm state image_url
  ].freeze
  PRICE_CHANGE_SHARE = 0.2
  PRICE_STEP_CENTS = 500_000 # $5,000, as in demo:change_property

  attr_reader :count

  def initialize(count:, random_seed: 42, now: Time.current)
    @count = count
    @rng = Random.new(random_seed)
    # Photos and write-ups draw from their own stream, so adding them didn't
    # change any of the other generated values.
    @text_rng = Random.new(random_seed + 1)
    @price_rng = Random.new(random_seed + 3)
    @extras = ListingExtras.new(random_seed:, now:)
    @now = now
    @suburbs = load_suburbs
    @type_picker = TYPES.flat_map { |type, (weight, _)| [ type ] * weight }
  end

  # Inserts `count` properties and returns how many were inserted.
  def call
    @extras.create_agents!
    count.times.each_slice(BATCH_SIZE).sum do |indexes|
      rows = indexes.map { |i| build_row(i) }
      inserted = Property.insert_all!(rows, returning: INSERTED_COLUMNS)
      # Sorted, so each random stream is used in the same order however
      # Postgres returns the rows.
      sorted = inserted.to_a.sort_by { _1["id"] }
      events = sorted.flat_map { history_for(_1) }
      PropertyEvent.insert_all!(events) if events.any?
      @extras.insert_for!(sorted)
      rows.size
    end
  end

  private

  attr_reader :rng

  def build_row(index)
    suburb = @suburbs.sample(random: rng)
    type = @type_picker.sample(random: rng)
    rooms = rooms_for(type)
    price_cents = withheld? ? nil : price_for(suburb["state"], type, rooms[:bedrooms])
    address = street_address(type)

    {
      street_address: address,
      suburb: suburb["suburb"],
      state: suburb["state"],
      postcode: suburb["postcode"],
      latitude: jitter(suburb["latitude"]),
      longitude: jitter(suburb["longitude"]),
      price_cents:,
      price_display: price_cents ? Property.format_price(price_cents) : WITHHELD_DISPLAYS.sample(random: rng),
      property_type: type,
      status: status,
      listed_at: listed_at(index),
      image_url: photo_for(type),
      agent_id: @extras.agent_id_for(suburb["state"]),
      **rooms
    }.then { |row| row.merge(description: description_for(type, address, suburb["suburb"], rooms, row[:status])) }
  end

  # A listing under offer, sold or withdrawn went there from for sale some
  # days after it was listed (never in the future).
  def status_event(property_id, status, listed_at)
    return if status == "for_sale"

    changed_at = [ listed_at + @text_rng.rand(1.0..30.0).days, @now ].min
    { property_id:, kind: "status_changed", from_value: "for_sale", to_value: status, created_at: changed_at }
  end

  # A listing's seeded history, oldest first: any price changes, then the
  # status change (price changes happen while it's for sale).
  def history_for(row)
    status_change = status_event(row["id"], row["status"], row["listed_at"])
    [ *price_events(row, before: status_change&.fetch(:created_at) || @now), status_change ].compact
  end

  # About one in five listings with a price had one or two changes, mostly
  # drops, in $5,000 steps like `demo:change_property`. Built backwards from
  # the current price, so the last change ends at it. None for a withheld
  # price: the page would show "Price updated" with no amounts anyway.
  def price_events(row, before:)
    current = row["price_cents"]
    return [] if current.nil? || @price_rng.rand >= PRICE_CHANGE_SHARE

    listed_at = row["listed_at"]
    return [] if before - listed_at < 2.days

    count = @price_rng.rand < 0.7 ? 1 : 2
    times = Array.new(count) { listed_at + @price_rng.rand(0.1..0.9) * (before - listed_at) }.sort
    to = current
    times.reverse.map do |changed_at|
      steps = @price_rng.rand(2..8)
      from = @price_rng.rand < 0.85 ? to + steps * PRICE_STEP_CENTS : [ to - steps * PRICE_STEP_CENTS, PRICE_STEP_CENTS ].max
      event = { property_id: row["id"], kind: "price_changed", from_value: from.to_s, to_value: to.to_s,
                created_at: changed_at }
      to = from
      event
    end.reverse
  end

  def photo_for(type)
    set = TYPE_PHOTOS.fetch(type).sample(random: @text_rng)
    format("%s/%s-%02d.webp", PHOTO_DIR, set, @text_rng.rand(1..PHOTO_SETS.fetch(set)))
  end

  # Three short paragraphs, like an agent's write-up.
  def description_for(type, address, suburb, rooms, status)
    for_sale = status == "for_sale"
    land = type == "land"
    openers = land ? LAND_OPENERS : OPENERS + (for_sale ? FOR_SALE_OPENERS : [])
    adjective = (land ? LAND_ADJECTIVES : ADJECTIVES).sample(random: @text_rng)
    opener = format(openers.sample(random: @text_rng), address:, suburb:, noun: TYPE_NOUNS.fetch(type), adjective:)
    candidates = land ? LAND_HIGHLIGHTS : HIGHLIGHTS.select { |_, fits| fits.call(rooms) }.keys
    highlights = candidates.sample(2, random: @text_rng).join(" ")
    closers = CLOSERS + (for_sale ? FOR_SALE_CLOSERS : [])
    [ opener, highlights, closers.sample(random: @text_rng) ].join("\n\n")
  end

  # ~10% withheld, so "Exclude price withheld" and price sorts have something to hide.
  def withheld? = rng.rand < 0.10

  # ~15% under offer, plus some sold and withdrawn that search must never show.
  def status
    roll = rng.rand
    if roll < 0.15 then "under_offer"
    elsif roll < 0.20 then "sold"
    elsif roll < 0.23 then "withdrawn"
    else "for_sale"
    end
  end

  # Rounded to the nearest $5,000, so equal prices (ties) are common, which
  # the keyset cursor must handle.
  def price_for(state, type, bedrooms)
    base = STATE_BASE_PRICE.fetch(state) * TYPES.fetch(type).last
    bedroom_factor = bedrooms.zero? ? 1.0 : 1 + 0.12 * (bedrooms - 3)
    dollars = base * bedroom_factor.clamp(0.6, 2.5) * rng.rand(0.7..1.4)
    (dollars / 5_000).round.clamp(20, nil) * 5_000 * 100
  end

  def rooms_for(type)
    case type
    when "house" then rooms(beds: [ 2, 3, 3, 3, 4, 4, 4, 5, 6 ], baths: 1..3, cars: 1..3, land: 300..900)
    when "apartment_unit" then rooms(beds: [ 0, 1, 1, 2, 2, 2, 3 ], baths: 1..2, cars: 0..2, land: nil)
    when "townhouse" then rooms(beds: [ 2, 3, 3, 4 ], baths: 1..3, cars: 1..2, land: 120..300)
    when "villa" then rooms(beds: [ 1, 2, 2, 3 ], baths: 1..2, cars: 1..1, land: 200..450)
    when "land" then rooms(beds: [ 0 ], baths: 0..0, cars: 0..0, land: 300..1_200)
    when "acreage" then rooms(beds: [ 3, 4, 4, 5 ], baths: 2..3, cars: 2..6, land: 8_000..80_000)
    when "rural" then rooms(beds: [ 3, 4, 5 ], baths: 1..3, cars: 2..4, land: 40_000..400_000)
    when "block_of_units" then rooms(beds: [ 4, 6, 8, 12 ], baths: 2..6, cars: 2..6, land: 600..1_500)
    when "retirement_living" then rooms(beds: [ 1, 2, 2 ], baths: 1..1, cars: 0..1, land: nil)
    end
  end

  def rooms(beds:, baths:, cars:, land:)
    bedrooms = beds.sample(random: rng)
    {
      bedrooms:,
      bathrooms: rng.rand(baths),
      car_spaces: rng.rand(cars),
      land_size_sqm: land && rng.rand(land)
    }
  end

  def street_address(type)
    street = "#{rng.rand(1..250)} #{STREET_NAMES.sample(random: rng)} #{STREET_SUFFIXES.sample(random: rng)}"
    %w[apartment_unit retirement_living].include?(type) ? "#{rng.rand(1..40)}/#{street}" : street
  end

  # Spread over the last 120 days at microsecond precision (Postgres's).
  # Edge cases for the keyset cursor on purpose: every 50th row reuses the
  # previous timestamp exactly, and every 50th row offset by 25 lands in the
  # previous row's millisecond with different microseconds, so values that
  # look equal in JSON (milliseconds) but differ in the database exist.
  def listed_at(index)
    @last_listed_at = nil if index.zero?
    if @last_listed_at
      return @last_listed_at if (index % 50).zero?
      return same_millisecond(@last_listed_at) if (index % 50) == 25
    end

    @last_listed_at = (@now - rng.rand(0.0..(120 * 86_400.0))).round(6)
  end

  def same_millisecond(time)
    microseconds = (time.usec % 1_000 + rng.rand(1..999)) % 1_000 # never the same value
    time.floor(3) + Rational(microseconds, 1_000_000)
  end


  # suburb,state,postcode,latitude,longitude with no quoted fields, so a plain
  # split is enough (csv is no longer a default gem in Ruby 3.4).
  def load_suburbs
    header, *lines = File.readlines(SUBURBS_CSV, chomp: true).reject(&:blank?)
    keys = header.split(",")
    lines.map { |line| keys.zip(line.split(",")).to_h }
  end

  # Spreads listings around the suburb centre (about 1 km either way).
  def jitter(coordinate) = (coordinate.to_f + rng.rand(-0.01..0.01)).round(6)
end
