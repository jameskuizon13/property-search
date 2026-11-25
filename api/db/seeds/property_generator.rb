# Builds realistic-looking Australian listings and bulk-inserts them with
# insert_all, so 10k rows take a few seconds. insert_all skips callbacks on
# purpose: seeding must not write property_events or broadcast anything.
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

  attr_reader :count

  def initialize(count:, random_seed: 42, now: Time.current)
    @count = count
    @rng = Random.new(random_seed)
    @now = now
    @suburbs = load_suburbs
    @type_picker = TYPES.flat_map { |type, (weight, _)| [ type ] * weight }
  end

  # Inserts `count` properties and returns how many were inserted.
  def call
    count.times.each_slice(BATCH_SIZE).sum do |indexes|
      rows = indexes.map { |i| build_row(i) }
      Property.insert_all!(rows)
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

    {
      street_address: street_address(type),
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
      **rooms
    }
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
