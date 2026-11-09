# Room activity: real use of the Room (a join, a phase transition, a Host action). Presence changes
# (connecting, going Away) are NOT activity. A Room idle for IDLE_LIMIT expires.
module Room::Activity
  extend ActiveSupport::Concern

  IDLE_LIMIT = 2.hours

  included do
    # Live Rooms with no activity for IDLE_LIMIT.
    scope :idle, -> { live.where(last_activity_at: ..IDLE_LIMIT.ago) }
  end

  class_methods do
    # Expires every idle Room. Returns the number expired.
    def expire_idle!
      idle.find_each.count(&:expire_if_idle!)
    end
  end

  # THE way to record Room activity. Call it from every join, kick, leave and Host action
  # (phase transitions already do via `enter_phase!`). Never call it for presence changes.
  def touch_activity!
    update_column(:last_activity_at, Time.current)
  end

  def expired? = expired_at.present?

  # Expires the Room if it is still live and idle (re-checked under the lock, so activity that just landed wins).
  # Sets `expired_at`, deletes the Players (clearing the Host link first) and keeps the Room and its Games;
  # game-player rows lose their Player link (DB nullify) and keep the copied nickname.
  def expire_if_idle!
    with_lock do
      next false if expired? || last_activity_at > IDLE_LIMIT.ago

      update_columns(expired_at: Time.current, host_player_id: nil)
      players.destroy_all
      true
    end
  end
end
