# What a property page shows beyond the listing row: the listing agent, the
# gallery after the cover photo, and upcoming open homes. Used by
# PropertyGenerator, which asks for an agent per row before inserting and
# hands over the inserted rows afterwards.
#
# Its own random stream (random_seed + 2), so adding it changed none of the
# other generated values. Open homes are relative to `now`, like listing dates.
class ListingExtras
  # From the ACMA's numbers reserved for TV, film and other fiction
  # (acma.gov.au "Phone numbers for use in TV shows, films and creative
  # works"): they belong to no one, so the demo never rings a real person.
  PHONES = [
    "0491 570 006", "0491 570 156", "0491 570 157", "0491 570 158", "0491 570 159", "0491 570 110",
    "0491 570 313", "0491 570 737", "0491 571 266", "0491 571 491", "0491 571 804", "0491 572 549",
    "0491 572 665", "0491 572 983", "0491 573 770", "0491 573 087", "0491 574 118", "0491 574 632",
    "0491 575 254", "0491 575 789", "0491 576 398", "0491 576 801", "0491 577 426", "0491 577 644"
  ].freeze
  FIRST_NAMES = %w[
    Olivia Jack Charlotte Noah Amelia William Mia Oliver Isla Thomas Grace Lucas
    Chloe Henry Ava James Sophie Liam Ella Ethan Zoe Daniel Ruby Samuel
  ].freeze
  LAST_NAMES = %w[
    Nguyen Smith Chen Williams Patel Brown Kelly Jones Singh Taylor Wilson Martin
    Lee Walker White Harris Ryan Clarke Thompson Murphy Young King Wright Scott
  ].freeze
  # Made-up agency names, one per state.
  AGENCIES = {
    "NSW" => "Harbour Lane Realty", "VIC" => "Laneway Property Co", "QLD" => "Sunlit Coast Real Estate",
    "WA" => "Swan Reach Property", "SA" => "Torrens Bend Realty", "TAS" => "Huon Ridge Property",
    "ACT" => "Capital Circle Realty", "NT" => "Top End Homes"
  }.freeze
  AGENTS_PER_STATE = PHONES.size / Property::STATES.size

  # set => [how many photos, caption read out to screen readers]
  GALLERY_SETS = {
    "living" => [ 6, "Living area" ], "kitchen" => [ 5, "Kitchen" ], "bedroom" => [ 5, "Bedroom" ],
    "bathroom" => [ 5, "Bathroom" ], "yard" => [ 4, "Backyard" ], "land" => [ 4, "The land" ],
    "rural" => [ 5, "Grounds" ], "apartment" => [ 6, "The building" ]
  }.freeze

  # Open homes, local time, in the next three weeks: mostly Saturdays, some
  # Sundays and weekday evenings. wday => [hour, minute] starts; each runs
  # 30 minutes.
  OPEN_HOME_STARTS = {
    6 => [ [ 9, 30 ], [ 10, 0 ], [ 10, 45 ], [ 11, 15 ], [ 12, 0 ], [ 13, 30 ], [ 14, 15 ], [ 15, 0 ] ],
    0 => [ [ 10, 30 ], [ 11, 0 ], [ 13, 0 ], [ 14, 30 ] ],
    3 => [ [ 17, 30 ], [ 18, 0 ] ],
    4 => [ [ 17, 15 ], [ 17, 45 ] ]
  }.freeze
  OPEN_HOME_DAYS = 21

  def initialize(random_seed:, now:)
    @rng = Random.new(random_seed + 2)
    @now = now
  end

  # Creates AGENTS_PER_STATE agents per state, each at that state's agency.
  def create_agents!
    names = FIRST_NAMES.shuffle(random: @rng).zip(LAST_NAMES.shuffle(random: @rng))
    rows = Property::STATES.flat_map.with_index do |state, s|
      AGENTS_PER_STATE.times.map do |a|
        n = s * AGENTS_PER_STATE + a
        first, last = names.fetch(n)
        { name: "#{first} #{last}", agency: AGENCIES.fetch(state), phone: PHONES.fetch(n),
          email: "#{first}.#{last}@example.com".downcase }
      end
    end
    ids = Agent.insert_all!(rows, returning: %w[id]).rows.flatten
    @agents_by_state = Property::STATES.zip(ids.each_slice(AGENTS_PER_STATE)).to_h
  end

  # An agent working in the listing's state.
  def agent_id_for(state) = @agents_by_state.fetch(state).sample(random: @rng)

  # `rows`: the inserted properties as hashes (PropertyGenerator::INSERTED_COLUMNS).
  # Sorted by id, so the random stream is used in the same order however
  # Postgres returns them.
  def insert_for!(rows)
    photos = []
    open_homes = []
    rows.sort_by { _1["id"] }.each do |row|
      id = row["id"]
      gallery = gallery_for(row["property_type"], row["bedrooms"], row["bathrooms"], row["land_size_sqm"],
                            row["image_url"])
      gallery.each.with_index(1) do |(url, caption), position|
        photos << { property_id: id, url:, caption:, position: }
      end
      open_homes.concat(open_homes_for(id, row["state"])) if row["status"] == "for_sale"
    end
    PropertyPhoto.insert_all!(photos) if photos.any?
    Inspection.insert_all!(open_homes) if open_homes.any?
  end

  private

  # The rooms a buyer expects to see, only those the listing has.
  def gallery_for(type, bedrooms, bathrooms, land, cover)
    sets =
      case type
      when "land" then %w[land land]
      when "acreage", "rural" then [ "rural", "living", "kitchen", ("bedroom" if bedrooms.positive?) ]
      when "block_of_units" then %w[apartment living kitchen]
      when "apartment_unit", "retirement_living"
        [ "living", "kitchen", ("bedroom" if bedrooms.positive?), ("bathroom" if bathrooms.positive?) ]
      else
        [ "living", "kitchen", ("bedroom" if bedrooms.positive?), ("bathroom" if bathrooms.positive?),
          ("yard" if land.to_i >= 200) ]
      end
    used = [ cover ]
    sets.compact.map do |set|
      count, caption = GALLERY_SETS.fetch(set)
      url = (1..count).map { |n| format("%s/%s-%02d.webp", PropertyGenerator::PHOTO_DIR, set, n) }.reject { used.include?(_1) }
                      .sample(random: @rng)
      used << url
      [ url, caption ]
    end
  end

  # None, one or two open homes on different days (about 40/40/20).
  def open_homes_for(property_id, state)
    roll = @rng.rand
    count = if roll < 0.4 then 0 elsif roll < 0.8 then 1 else 2 end
    return [] if count.zero?

    zone = ActiveSupport::TimeZone[Property::TIME_ZONES.fetch(state)]
    today = @now.in_time_zone(zone).to_date
    days = (1..OPEN_HOME_DAYS).map { today + _1 }.select { OPEN_HOME_STARTS.key?(_1.wday) }
    days.sample(count, random: @rng).sort.map do |day|
      hour, minute = OPEN_HOME_STARTS.fetch(day.wday).sample(random: @rng)
      starts_at = zone.local(day.year, day.month, day.day, hour, minute)
      { property_id:, starts_at:, ends_at: starts_at + 30.minutes }
    end
  end
end
