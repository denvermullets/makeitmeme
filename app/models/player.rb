class Player < ApplicationRecord
  NICKNAME_MAX = 16

  belongs_to :room

  validates :nickname, presence: true, length: { maximum: NICKNAME_MAX },
                       uniqueness: { scope: :room_id, case_sensitive: false }
  validates :browser_token, presence: true

  def self.new_browser_token
    SecureRandom.urlsafe_base64(24)
  end
end
