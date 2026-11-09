class Player < ApplicationRecord
  NICKNAME_MAX = 16

  AWAY_GRACE = 20.seconds

  belongs_to :room

  # Here = not Away. One query for game logic: `Player.here` / `player.here?`. (Not `present`: that name is
  # ActiveSupport's "not blank" on every object.)
  scope :here, -> { where(away_at: nil) }
  scope :away, -> { where.not(away_at: nil) }

  validates :nickname, presence: true, length: { maximum: NICKNAME_MAX },
                       uniqueness: { scope: :room_id, case_sensitive: false }
  validates :browser_token, presence: true

  after_create_commit :broadcast_joined
  after_destroy_commit :broadcast_left

  def away? = away_at.present?
  def here? = !away?

  # Several open tabs count as one presence: the count only reaches 0 when the last one closes.
  def connected!
    was_away = with_lock do
      increment(:connections_count)
      increment(:presence_token)
      away?.tap do
        self.away_at = nil
        save!
      end
    end
    return unless was_away

    broadcast_away_marker
    room.broadcast_start_gate!
  end

  def disconnected!
    with_lock do
      update!(connections_count: [connections_count - 1, 0].max)
      schedule_away_check if connections_count.zero?
    end
  end

  # Called by the grace job: Away only if still unconnected and nobody reconnected since the job was scheduled.
  def go_away!(token)
    went_away = with_lock do
      next false unless connections_count.zero? && presence_token == token && here?

      update!(away_at: Time.current)
    end
    return unless went_away

    broadcast_away_marker
    room.player_went_away!(self)
  end

  # A restart drops every cable connection without running unsubscribe, so counts in the database are stale.
  # Zero them and give each Player who was not Away a fresh grace: browsers reconnect within seconds and never show as
  # Away, the rest go Away as usual. Players already Away get no job. Single box only (see
  # config/initializers/presence_reset.rb).
  def self.reset_presence!
    find_each(&:reset_connections!)
  end

  def reset_connections!
    with_lock do
      update!(connections_count: 0)
      next unless here?

      increment!(:presence_token)
      schedule_away_check
    end
  end

  def self.new_browser_token
    SecureRandom.urlsafe_base64(24)
  end

  private

  # The grace job carries the token it was scheduled for; it is enqueued once the surrounding lock has committed.
  def schedule_away_check
    token = presence_token
    ActiveRecord.after_all_transactions_commit do
      PresenceGraceJob.set(wait: AWAY_GRACE).perform_later(id, token)
    end
  end

  # Broadcasts are deltas for Players already on the Waiting page (a reload renders the full list). Order matters:
  # the list item, then the Host's kick slot inside it, then the Start gate.
  def broadcast_joined
    broadcast_append_to room, target: 'players'
    offer_kick_to_host
    room.broadcast_start_gate!
  end

  def broadcast_left
    broadcast_remove_to room
    Room.find_by(id: room_id)&.broadcast_start_gate!
  end

  # The appended list item is shared, so it has no kick action; the Host's private stream fills in the slot.
  def offer_kick_to_host
    return unless room.host

    broadcast_replace_to room, room.host, target: "kick_#{ActionView::RecordIdentifier.dom_id(self)}",
                                          partial: 'players/kick', locals: { player: self, room:, viewer: room.host }
  end

  def broadcast_away_marker
    broadcast_replace_to room, target: "away_#{ActionView::RecordIdentifier.dom_id(self)}",
                               partial: 'players/away_marker', locals: { player: self }
  end
end
