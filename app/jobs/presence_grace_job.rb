# Marks a Player Away once the grace after their last connection closed has run out. Carries the presence token
# it was scheduled for, so a Player who reconnected in the meantime (token moved on) is left alone (cf. ADR 0001).
class PresenceGraceJob < ApplicationJob
  retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: 1.second, attempts: 5

  def perform(player_id, presence_token)
    Player.find_by(id: player_id)&.go_away!(presence_token)
  end
end
