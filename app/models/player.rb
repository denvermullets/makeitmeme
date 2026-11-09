class Player < ApplicationRecord
  NICKNAME_MAX = 16

  AWAY_GRACE = 20.seconds

  belongs_to :room

  # Present = not Away. One query for game logic: `Player.present` / `player.present?`.
  scope :present, -> { where(away_at: nil) }
  scope :away, -> { where.not(away_at: nil) }

  validates :nickname, presence: true, length: { maximum: NICKNAME_MAX },
                       uniqueness: { scope: :room_id, case_sensitive: false }
  validates :browser_token, presence: true

  # Broadcasts are deltas for Players already on the Waiting page; a reload renders the full list.
  after_create_commit -> { broadcast_append_to room, target: 'players' }
  after_create_commit :offer_kick_to_host
  after_destroy_commit -> { broadcast_remove_to room }

  def away? = away_at.present?
  def present? = !away?

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
    broadcast_away_marker if was_away
  end

  def disconnected!
    with_lock do
      update!(connections_count: [connections_count - 1, 0].max)
      PresenceGraceJob.set(wait: AWAY_GRACE).perform_later(id, presence_token) if connections_count.zero?
    end
  end

  # Called by the grace job: Away only if still unconnected and nobody reconnected since the job was scheduled.
  def go_away!(token)
    went_away = with_lock do
      next false unless connections_count.zero? && presence_token == token && present?

      update!(away_at: Time.current)
    end
    return unless went_away

    broadcast_away_marker
    room.player_went_away!(self)
  end

  # A restart drops every cable connection without running unsubscribe, so counts in the database are stale.
  # Zero them and give each Player who was not Away a fresh grace: browsers reconnect within seconds and never show as
  # Away, the rest go Away as usual. Players already Away get no job. Single box only (see config/puma.rb).
  def self.reset_presence!
    find_each do |player|
      player.with_lock do
        player.update!(connections_count: 0)
        player.schedule_boot_grace if player.present?
      end
    end
  end

  def schedule_boot_grace
    increment!(:presence_token)
    PresenceGraceJob.set(wait: AWAY_GRACE).perform_later(id, presence_token)
  end

  def self.new_browser_token
    SecureRandom.urlsafe_base64(24)
  end

  private

  # The appended list item is shared, so it has no kick action; the Host's private stream fills in the slot.
  def offer_kick_to_host
    return unless room.host

    broadcast_replace_to room, room.host, target: "kick_#{ActionView::RecordIdentifier.dom_id(self)}",
                                          partial: 'players/kick', locals: { player: self, viewer: room.host }
  end

  def broadcast_away_marker
    broadcast_replace_to room, target: "away_#{ActionView::RecordIdentifier.dom_id(self)}",
                               partial: 'players/away_marker', locals: { player: self }
  end
end
