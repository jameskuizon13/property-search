class User < ApplicationRecord
  PASSWORD_LENGTH = 12..72 # 72 is bcrypt's byte limit

  has_secure_password

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :name, with: ->(name) { name.strip }

  validates :email, presence: true,
                    length: { maximum: 254 },
                    format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: true
  validates :name, presence: true, length: { maximum: 100 }
  validates :password, length: { in: PASSWORD_LENGTH }, allow_nil: true
end
