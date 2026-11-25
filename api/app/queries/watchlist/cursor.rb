module Watchlist
  # Opaque keyset cursor for GET /watchlist: the last row's
  # [watchlist_items.created_at, watchlist_items.id]. Signed with its own key,
  # so it can't be edited and a search cursor is never accepted here (or the
  # other way round). Decoded values are type-checked before they reach SQL.
  #
  # created_at is stored as integer microseconds, Postgres's precision, for the
  # same reason as Properties::Cursor: rows sharing a millisecond would
  # otherwise be skipped or repeated.
  class Cursor
    Decoded = Data.define(:watched_at, :id)

    def self.verifier
      @verifier ||= ActiveSupport::MessageVerifier.new(
        Rails.application.key_generator.generate_key("watchlist/cursor"),
        digest: "SHA256", serializer: JSON, url_safe: true
      )
    end

    def self.encode(watched_at:, id:)
      verifier.generate({ "v" => [ Properties::Cursor.microseconds(watched_at), id ] })
    end

    # Returns a Decoded, or nil if the cursor is forged or malformed.
    def self.decode(token)
      payload = verifier.verified(token)
      return unless payload.is_a?(Hash) && payload["v"].is_a?(Array) && payload["v"].size == 2

      microseconds, id = payload["v"]
      return unless microseconds.is_a?(Integer) && id.is_a?(Integer)

      Decoded.new(watched_at: Time.at(Rational(microseconds, 1_000_000)).utc, id:)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
