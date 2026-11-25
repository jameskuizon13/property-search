module Properties
  # Opaque keyset cursor: the last row's [sort value, id], plus the sort it
  # belongs to. Signed, so it can't be edited; decoded values are type-checked
  # before they reach SQL. (Encrypting it is a Milestone 9 item.)
  #
  # listed_at is stored as integer microseconds, Postgres's precision. JSON
  # times only carry milliseconds, so a serialised time would skip or repeat
  # rows that share a millisecond.
  class Cursor
    Decoded = Data.define(:value, :id)

    # JSON (never Marshal) and URL-safe base64, so the cursor survives a
    # query string as-is. The key is derived from secret_key_base.
    def self.verifier
      @verifier ||= ActiveSupport::MessageVerifier.new(
        Rails.application.key_generator.generate_key("properties/search_cursor"),
        digest: "SHA256", serializer: JSON, url_safe: true
      )
    end

    def self.encode(sort:, record:)
      value = sort == "newest" ? microseconds(record.listed_at) : record.price_cents
      verifier.generate({ "s" => sort, "v" => [ value, record.id ] })
    end

    # Returns a Decoded, or nil if the cursor is forged, malformed or was
    # issued for a different sort.
    def self.decode(token, sort:)
      payload = verifier.verified(token)
      return unless payload.is_a?(Hash) && payload["s"] == sort

      value, id = payload["v"]
      return unless value.is_a?(Integer) && id.is_a?(Integer) && payload["v"].size == 2

      Decoded.new(value: sort == "newest" ? Time.at(Rational(value, 1_000_000)).utc : value, id:)
    rescue ArgumentError, TypeError
      nil
    end

    def self.microseconds(time) = (time.to_r * 1_000_000).to_i
  end
end
