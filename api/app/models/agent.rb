# A listing agent: who a buyer calls or emails about a property.
class Agent < ApplicationRecord
  # The FK nullifies on delete, so no dependent: is needed.
  has_many :properties

  normalizes :name, :agency, :phone, with: ->(value) { value.strip }
  normalizes :email, with: ->(value) { value.strip.downcase }

  validates :name, :agency, presence: true, length: { maximum: 100 }
  # Digits, spaces and an optional leading +, as people write them ("0491 570 156").
  validates :phone, format: { with: /\A\+?[0-9 ]{8,20}\z/ }
  # Stricter than URI::MailTo::EMAIL_REGEXP, which allows "?", "#" and "%": the
  # page puts the address in a mailto: link, where those (or a %-encoded "?" or
  # ",") could add a recipient or a bcc, or cut off the subject.
  validates :email, format: { with: /\A[a-z0-9._+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}\z/ },
                    length: { maximum: 254 }
end
