module Watchlist
  # One user's watched properties, most recently added first, keyset-paginated.
  #
  #   result = Watchlist::ListQuery.new(params, user: current_user).call
  #   # => Result(records:, meta:)  (ActiveModel::ValidationError -> 422)
  #
  # Not limited to Property.active: a watched property that sells or is
  # withdrawn stays on the watchlist with its new status.
  #
  # Always scoped to the given user's rows, so there is no way to ask for
  # someone else's watchlist (no IDOR).
  class ListQuery
    include ActiveModel::Validations

    INTEGER = /\A\d+\z/
    AFTER_CURSOR = "(watchlist_items.created_at, watchlist_items.id) < (?, ?)".freeze

    Result = Data.define(:records, :meta)

    attr_reader :limit, :cursor

    validate :validate_params

    def initialize(params, user:)
      @params = params.to_h.stringify_keys
      @user = user
      @errors_from_parsing = Hash.new { |hash, key| hash[key] = [] }
      @limit = parse_limit
      @cursor = parse_cursor
    end

    def call
      validate!
      rows = relation.to_a
      has_more = rows.size > limit
      rows = rows.first(limit)

      meta = { limit:, has_more: }
      meta[:next_cursor] = Cursor.encode(watched_at: rows.last.watched_at, id: rows.last.watchlist_item_id) if has_more
      # First batch only, like search; no COUNT when it already holds every row.
      meta[:total_count] = has_more ? user.watchlist_items.count : rows.size if cursor.nil?

      Result.new(records: rows, meta:)
    end

    # One page as Property rows, each carrying the watchlist item's id and
    # created_at (watched_at) for the cursor. One query, served by the
    # (user_id, created_at DESC, id DESC) index, then a primary-key lookup
    # per row on properties.
    def relation
      validate!
      items = WatchlistItem.arel_table
      scope = Property.joins(:watchlist_items).where(watchlist_items: { user_id: user.id })
      scope = scope.where(AFTER_CURSOR, decoded_cursor.watched_at, decoded_cursor.id) if cursor
      scope.select("properties.*", "watchlist_items.id AS watchlist_item_id", "watchlist_items.created_at AS watched_at")
           .order(items[:created_at].desc, items[:id].desc)
           .limit(limit + 1)
    end

    private

    attr_reader :params, :user

    def parse_limit
      raw = scalar("limit", :limit)
      return pagination.default_limit if raw.nil? || raw == ""
      return add_error(:limit, "must be a whole number") unless raw.match?(INTEGER)

      value = raw.to_i
      range = 1..pagination.max_limit
      return add_error(:limit, "must be between #{range.min} and #{range.max}") unless range.cover?(value)

      value
    end

    def parse_cursor
      raw = scalar("cursor", :cursor)
      raw.presence
    end

    # A param that must be a single string (not an array or a hash).
    def scalar(key, attribute)
      value = params[key]
      return if value.nil?
      return add_error(attribute, "must be a single value") unless value.is_a?(String)
      return add_error(attribute, "contains a null byte") if value.include?("\u0000")

      value
    end

    # Records the error and returns nil, so a bad value never reaches SQL.
    def add_error(attribute, message)
      @errors_from_parsing[attribute] << message
      nil
    end

    def validate_params
      @errors_from_parsing.each { |attribute, messages| messages.each { |m| errors.add(attribute, m) } }
      errors.add(:cursor, "is invalid") if cursor && decoded_cursor.nil?
    end

    def decoded_cursor
      @decoded_cursor ||= Cursor.decode(cursor)
    end

    def pagination = Rails.configuration.x.pagination
  end
end
