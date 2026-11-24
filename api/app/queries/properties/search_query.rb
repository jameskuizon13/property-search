module Properties
  # Search, filter, sort and keyset-paginate active listings.
  #
  #   query = Properties::SearchQuery.new(params, user: current_user)
  #   query.validate!        # ActiveModel::ValidationError -> 422
  #   result = query.call    # => Result(records:, meta:)
  #   query.relation.explain(:analyze)   # the exact SQL a page runs
  #
  # Params use the API's camelCase names (minPrice, propertyTypes, ...).
  # Values arrive as strings and are checked strictly: `minBedrooms=banana`
  # is a 422, not silently ignored. Error details use snake_case keys.
  class SearchQuery
    include ActiveModel::Validations

    SORTS = %w[newest price_asc price_desc].freeze
    MIN_Q_LENGTH = 2   # shorter q is ignored, so one letter never scans the table
    MAX_Q_LENGTH = 100
    MAX_PRICE = 1_000_000_000 # whole AUD; keeps price * 100 well inside bigint
    MAX_BEDROOMS = 20
    INTEGER = /\A\d+\z/
    BOOLEANS = { "true" => true, "1" => true, "false" => false, "0" => false }.freeze

    # Rows after the cursor. Price low->high reads forwards (>); newest and
    # price high->low read backwards (<) over the same indexes.
    CURSOR_CONDITIONS = {
      "newest" => "(properties.listed_at, properties.id) < (?, ?)",
      "price_asc" => "(properties.price_cents, properties.id) > (?, ?)",
      "price_desc" => "(properties.price_cents, properties.id) < (?, ?)"
    }.freeze

    Result = Data.define(:records, :meta)

    attr_reader :q, :min_price, :max_price, :min_bedrooms, :property_types, :sort, :cursor, :limit,
                :exclude_under_offer, :exclude_price_withheld

    validate :validate_params

    def initialize(params, user: nil)
      @params = params.to_h.stringify_keys
      @user = user
      @errors_from_parsing = Hash.new { |hash, key| hash[key] = [] }
      parse
    end

    def call
      validate!
      rows = relation.to_a
      has_more = rows.size > limit
      rows = rows.first(limit)

      meta = { limit:, has_more: }
      meta[:next_cursor] = Cursor.encode(sort:, record: rows.last) if has_more
      # Counted once, for the first batch only; later batches reuse it.
      meta[:total_count] = filtered.count if cursor.nil?

      Result.new(records: rows, meta:)
    end

    # One page: filters, cursor, order, limit + 1 (the extra row decides
    # hasMore), and `watched` from a single LEFT JOIN rather than a lookup
    # per row.
    def relation
      validate!
      scope = filtered
      scope = after_cursor(scope) if cursor
      with_watched(scope).order(order).limit(limit + 1)
    end

    # The filtered rows, before paging and the `watched` select. COUNT runs on
    # this: calling .count on the relation with the custom select breaks SQL.
    def filtered
      scope = Property.active
      scope = scope.for_sale if exclude_under_offer
      # Price sorts leave out withheld prices, and so does the count.
      scope = scope.where.not(price_cents: nil) if exclude_price_withheld || price_sort?
      scope = scope.where(price_cents: (min_price * 100)..) if min_price
      scope = scope.where(price_cents: ..(max_price * 100)) if max_price
      scope = scope.where(bedrooms: min_bedrooms..) if min_bedrooms
      scope = scope.where(property_type: property_types) if property_types.present?
      scope = matching_text(scope) if q
      scope
    end

    private

    attr_reader :params, :user

    def price_sort? = sort != "newest"

    # suburb/street contain q (trigram GIN indexes), or postcode starts with
    # it (text_pattern_ops index), so "30" finds 3065. Postgres combines the
    # three with a BitmapOr.
    def matching_text(scope)
      escaped = Property.sanitize_sql_like(q)
      scope.where(
        "properties.suburb ILIKE :contains OR properties.street_address ILIKE :contains OR properties.postcode LIKE :prefix",
        contains: "%#{escaped}%", prefix: "#{escaped}%"
      )
    end

    def order
      case sort
      when "newest" then { listed_at: :desc, id: :desc }
      when "price_asc" then { price_cents: :asc, id: :asc }
      when "price_desc" then { price_cents: :desc, id: :desc }
      end
    end

    # Row-value comparison, matching the (sort column, id) indexes.
    def after_cursor(scope)
      scope.where(CURSOR_CONDITIONS.fetch(sort), decoded_cursor.value, decoded_cursor.id)
    end

    def with_watched(scope)
      return scope.select("properties.*", "FALSE AS watched") unless user

      join = Property.sanitize_sql_array([
        "LEFT JOIN watchlist_items ON watchlist_items.property_id = properties.id AND watchlist_items.user_id = ?",
        user.id
      ])
      scope.joins(join).select("properties.*", "(watchlist_items.id IS NOT NULL) AS watched")
    end

    def decoded_cursor
      @decoded_cursor ||= Cursor.decode(cursor, sort:)
    end

    # --- parsing -----------------------------------------------------------

    def parse
      @q = parse_q
      @min_price = parse_integer("minPrice", :min_price, 0..MAX_PRICE)
      @max_price = parse_integer("maxPrice", :max_price, 0..MAX_PRICE)
      @min_bedrooms = parse_integer("minBedrooms", :min_bedrooms, 0..MAX_BEDROOMS)
      @property_types = parse_property_types
      @exclude_under_offer = parse_boolean("excludeUnderOffer", :exclude_under_offer)
      @exclude_price_withheld = parse_boolean("excludePriceWithheld", :exclude_price_withheld)
      @sort = parse_sort
      @limit = parse_integer("limit", :limit, 1..pagination.max_limit) || pagination.default_limit
      @cursor = parse_cursor
    end

    def parse_q
      value = scalar("q", :q)&.strip
      return if value.nil? || value.length < MIN_Q_LENGTH
      return add_error(:q, "is too long (maximum is #{MAX_Q_LENGTH} characters)") if value.length > MAX_Q_LENGTH

      value
    end

    def parse_integer(key, attribute, range)
      raw = scalar(key, attribute)
      return if raw.nil? || raw == ""
      return add_error(attribute, "must be a whole number") unless raw.match?(INTEGER)

      value = raw.to_i
      return add_error(attribute, "must be between #{range.min} and #{range.max}") unless range.cover?(value)

      value
    end

    def parse_boolean(key, attribute)
      raw = scalar(key, attribute)
      return false if raw.nil? || raw == ""
      unless BOOLEANS.key?(raw)
        add_error(attribute, "must be true or false")
        return false
      end

      BOOLEANS.fetch(raw)
    end

    # propertyTypes[]=house&propertyTypes[]=villa, or propertyTypes=house,villa.
    def parse_property_types
      raw = params["propertyTypes"]
      values = case raw
      when nil then []
      when String then raw.split(",")
      when Array then raw
      end
      return add_error(:property_types, "must be a list of strings") unless values&.all?(String)

      values = values.map(&:strip).compact_blank.uniq
      unknown = values - Property::PROPERTY_TYPES.keys
      return add_error(:property_types, "has unknown values: #{unknown.join(', ')}") if unknown.any?

      values
    end

    def parse_sort
      raw = scalar("sort", :sort)
      return "newest" if raw.nil? || raw == ""
      unless SORTS.include?(raw)
        add_error(:sort, "must be one of: #{SORTS.join(', ')}")
        return "newest"
      end

      raw
    end

    def parse_cursor
      raw = scalar("cursor", :cursor)
      return if raw.nil? || raw == ""

      raw
    end

    # A param that must be a single string (not an array or a hash).
    def scalar(key, attribute)
      value = params[key]
      return if value.nil?
      return add_error(attribute, "must be a single value") unless value.is_a?(String)

      value
    end

    # Records the error and returns nil, so a bad value never reaches SQL.
    def add_error(attribute, message)
      @errors_from_parsing[attribute] << message
      nil
    end

    def validate_params
      @errors_from_parsing.each { |attribute, messages| messages.each { |m| errors.add(attribute, m) } }
      if min_price && max_price && min_price > max_price
        errors.add(:max_price, "must be greater than or equal to min_price")
      end
      # A forged cursor, or one issued for a different sort.
      errors.add(:cursor, "is invalid") if cursor && decoded_cursor.nil?
    end

    def pagination = Rails.configuration.x.pagination
  end
end
