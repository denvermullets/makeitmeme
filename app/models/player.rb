class Player < ApplicationRecord
  NICKNAME_MAX = 16

  belongs_to :room

  validates :nickname, presence: true, length: { maximum: NICKNAME_MAX },
                       uniqueness: { scope: :room_id, case_sensitive: false }
  validates :browser_token, presence: true

  # Broadcasts are deltas for Players already on the Waiting page; a reload renders the full list.
  after_create_commit -> { broadcast_append_to room, target: 'players' }

  def self.new_browser_token
    SecureRandom.urlsafe_base64(24)
  end
end
