class Property < ApplicationRecord
  STATES = %w[NSW VIC QLD WA SA TAS ACT NT].freeze
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

  SMALLINT_MAX = 32_767

  # String-backed enums (not integers), so SQL and index predicates stay
  # readable. validate: true turns an unknown value into a 422, not a 500.
  enum :status, STATUSES.index_by(&:itself), default: "for_sale", validate: true
  enum :property_type, PROPERTY_TYPES.keys.index_by(&:itself), validate: true

  # The FKs cascade in the database, so no dependent: callbacks are needed.
  has_many :property_events
  has_many :watchlist_items

  scope :active, -> { where(status: ACTIVE_STATUSES) }

  normalizes :street_address, :suburb, :price_display, with: ->(value) { value.strip }
  normalizes :state, with: ->(value) { value.strip.upcase }
  normalizes :postcode, with: ->(value) { value.strip }

  validates :street_address, presence: true, length: { maximum: 200 }
  validates :suburb, presence: true, length: { maximum: 100 }
  validates :state, inclusion: { in: STATES }
  validates :postcode, format: { with: /\A\d{4}\z/, message: "must be 4 digits" }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :price_display, presence: true, length: { maximum: 100 }
  validates :bedrooms, :bathrooms, :car_spaces,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: SMALLINT_MAX }
  validates :land_size_sqm, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true
  validates :listed_at, presence: true

  # "$850,000" from 85_000_000 cents.
  def self.format_price(cents)
    ActiveSupport::NumberHelper.number_to_currency(cents / 100, unit: "$", precision: 0)
  end

  def price_withheld? = price_cents.nil?
  def active? = ACTIVE_STATUSES.include?(status)
end
