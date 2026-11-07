class Room < ApplicationRecord
  CODE_LETTERS = ('A'..'Z').to_a.freeze
  CODE_LENGTH = 4
  CODE_ATTEMPTS = 10

  enum :phase, { waiting: 'waiting' }, default: :waiting

  has_many :players, dependent: :destroy
  belongs_to :host, class_name: 'Player', foreign_key: :host_player_id, optional: true, inverse_of: false

  scope :live, -> { where(expired_at: nil) }

  # Room game operation: create a Room and its Host Player.
  # Raises ActiveRecord::RecordInvalid when the nickname is not acceptable.
  def self.create_with_host(nickname:, browser_token:, codes: nil)
    transaction do
      room = insert_with_unique_code(codes || random_codes)
      host = room.players.create!(nickname:, browser_token:, joined_at: Time.current)
      room.update!(host:)
      room
    end
  end

  # An endless stream of candidate codes. Tests pass their own `codes:` to force a clash.
  def self.random_codes
    Enumerator.produce { Array.new(CODE_LENGTH) { CODE_LETTERS.sample }.join }
  end

  # A clash on the partial unique index is retried with a fresh code. The savepoint
  # keeps the outer transaction usable after the failed insert.
  def self.insert_with_unique_code(codes)
    attempts = 0
    begin
      transaction(requires_new: true) { create!(code: codes.next, last_activity_at: Time.current) }
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      raise if attempts >= CODE_ATTEMPTS

      retry
    end
  end
  private_class_method :insert_with_unique_code

  def host?(player)
    player.present? && player.id == host_player_id
  end

  def player_for(browser_token)
    return if browser_token.blank?

    players.find_by(browser_token:)
  end
end
