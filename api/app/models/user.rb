class User < ApplicationRecord
  PASSWORD_LENGTH = 12..72 # 72 is bcrypt's byte limit
  ROLES = %w[user admin].freeze

  has_secure_password

  # The FK cascades in the database, so no dependent: callback is needed.
  has_many :watchlist_items

  # String-backed, with a CHECK in the database. Never accepted as a param:
  # sign-up always creates a normal user; only the seed makes an admin.
  enum :role, ROLES.index_by(&:itself), default: "user", validate: true

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :name, with: ->(name) { name.strip }

  validates :email, presence: true,
                    length: { maximum: 254 },
                    format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: true
  validates :name, presence: true, length: { maximum: 100 }
  validates :password, length: { in: PASSWORD_LENGTH }, allow_nil: true
end
