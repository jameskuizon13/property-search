class Property < ApplicationRecord
  STATES = %w[NSW VIC QLD WA SA TAS ACT NT].freeze
  # Each state's local time, for open-home times (shown in the listing's time,
  # not the viewer's).
  TIME_ZONES = {
    "NSW" => "Australia/Sydney", "VIC" => "Australia/Melbourne", "QLD" => "Australia/Brisbane",
    "WA" => "Australia/Perth", "SA" => "Australia/Adelaide", "TAS" => "Australia/Hobart",
    "ACT" => "Australia/Sydney", "NT" => "Australia/Darwin"
  }.freeze
  STATUSES = %w[for_sale under_offer sold withdrawn].freeze
  # Search only ever shows these. Property.active turns them into
  # `status IN ('for_sale', 'under_offer')`, the exact predicate of the
  # partial indexes, so Postgres can use them.
  ACTIVE_STATUSES = %w[for_sale under_offer].freeze

  # value => label. A short, realestate.com.au-style list; the API serves it
  # from GET /property_types so the UI never hard-codes it.
  PROPERTY_TYPES = {
    "house" => "House",
    "apartment_unit" => "Apartment & Unit",
    "townhouse" => "Townhouse",
    "villa" => "Villa",
    "land" => "Land",
    "acreage" => "Acreage",
    "rural" => "Rural",
    "block_of_units" => "Block of Units",
    "retirement_living" => "Retirement Living"
  }.freeze

  # Photos are the web app's own static files (web/public/images); see
  # docs/features/property-detail.md.
  PHOTO_PATH = %r{\A/images/[a-z0-9/_-]+\.(webp|jpe?g|png)\z}

  SMALLINT_MAX = 32_767
  INTEGER_MAX = 2_147_483_647
  # $1 billion: far above any listing, and keeps search's price * 100 math
  # well inside bigint. Without caps an oversized value passes validation
  # and then fails the save with a RangeError (a 500, not a 422).
  MAX_PRICE_CENTS = 100_000_000_000

  # String-backed enums (not integers), so SQL and index predicates stay
  # readable. validate: true turns an unknown value into a 422, not a 500.
  enum :status, STATUSES.index_by(&:itself), default: "for_sale", validate: true
  enum :property_type, PROPERTY_TYPES.keys.index_by(&:itself), validate: true

  # The FKs cascade in the database, so no dependent: callbacks are needed.
  # Deleting a property also deletes its change history (FK cascade). Admins
  # are steered to the softer option, status `withdrawn`, which keeps it.
  has_many :property_events
  has_many :watchlist_items
  has_many :inspections
  has_many :photos, -> { order(:position) }, class_name: "PropertyPhoto", inverse_of: :property
  # Optional: a listing can exist before an agent is assigned (and keeps going
  # if its agent is removed; the FK nullifies).
  belongs_to :agent, optional: true

  scope :active, -> { where(status: ACTIVE_STATUSES) }

  # Price and status changes are what watchers get alerted on (Domain's
  # Shortlist alerts). The event row is written inside the save's transaction,
  # so the change and its history are saved together or not at all; watchers
  # are told only after commit, so they never hear about a rolled-back change.
  # In after-callbacks `price_cents_changed?` is already false, hence
  # saved_change_to_*. `update_all`/`insert_all` skip all of this (the seed
  # relies on that); every other write goes through update!. The commit
  # callback sees only the last save's changes, so make one save per
  # transaction (every caller does): a second save in the same transaction
  # would log the first change but not broadcast it.
  after_update :record_change_events, if: :price_or_status_changed?
  after_update_commit :notify_watchers, if: :price_or_status_changed?
  # Any change can move search results or counts (see SearchCache).
  after_commit :bump_search_cache, on: %i[create update destroy]

  normalizes :street_address, :suburb, :price_display, with: ->(value) { value.strip }
  normalizes :state, with: ->(value) { value.strip.upcase }
  normalizes :postcode, with: ->(value) { value.strip }

  validates :street_address, presence: true, length: { maximum: 200 }
  validates :suburb, presence: true, length: { maximum: 100 }
  validates :state, inclusion: { in: STATES }
  validates :postcode, format: { with: /\A\d{4}\z/, message: "must be 4 digits" }
  validates :price_cents, numericality: { only_integer: true, in: 0..MAX_PRICE_CENTS }, allow_nil: true
  validates :price_display, presence: true, length: { maximum: 100 }
  validates :bedrooms, :bathrooms, :car_spaces,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: SMALLINT_MAX }
  validates :land_size_sqm, numericality: { only_integer: true, in: 0..INTEGER_MAX }, allow_nil: true
  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true
  validates :listed_at, presence: true
  validates :description, length: { maximum: 5_000 }
  validates :image_url, format: { with: PHOTO_PATH }, length: { maximum: 500 }, allow_nil: true

  # "$850,000" from 85_000_000 cents.
  def self.format_price(cents)
    ActiveSupport::NumberHelper.number_to_currency(cents / 100, unit: "$", precision: 0)
  end

  def price_withheld? = price_cents.nil?
  def active? = ACTIVE_STATUSES.include?(status)

  private

  def price_or_status_changed? = saved_change_to_price_cents? || saved_change_to_status?

  def record_change_events
    if saved_change_to_price_cents?
      from, to = saved_change_to_price_cents
      property_events.create!(kind: "price_changed", from_value: from&.to_s, to_value: to&.to_s)
    end
    if saved_change_to_status?
      from, to = saved_change_to_status
      property_events.create!(kind: "status_changed", from_value: from, to_value: to)
    end
  end

  def notify_watchers = PropertyChangeNotifier.call(self)

  def bump_search_cache = SearchCache.bump!
end
