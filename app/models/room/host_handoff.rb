# Passing the Host role to another Player. Used when the Host goes Away (the next present Player takes over, in any
# phase, and it never goes back) and by Leave Room (the earliest-joined remaining Player, or nobody).
module Room::HostHandoff
  extend ActiveSupport::Concern

  # Hands the Host role from `from` to the Player who joined earliest. Does nothing unless `from` is the Host.
  # By default only present Players qualify and, if there is none, the Host stays. With `fallback_to_away: true`
  # (Leave) every other Player qualifies and, if there is none, the Room is left without a Host.
  # Returns the new Host, or nil when nobody took over. Safe inside a caller's lock/transaction: the broadcasts
  # go out once everything has committed.
  def hand_off_host!(from:, fallback_to_away: false)
    changed = false
    successor = with_lock do
      next unless host_player_id == from.id

      candidates = players.where.not(id: from.id)
      candidates = candidates.present unless fallback_to_away
      candidate = candidates.order(:joined_at, :id).first
      changed = candidate.present? || fallback_to_away
      update!(host: candidate) if changed
      candidate
    end
    ActiveRecord.after_all_transactions_commit { broadcast_host_change } if changed
    successor
  end

  private

  # Every phone sees who the Host is; the Host-only controls (kick buttons, Start gate, Packs, Play again) are
  # re-sent per Player, on that Player's own stream so a list item and its kick slot cannot arrive out of order.
  def broadcast_host_change
    members = players.reload.to_a
    members.each do |viewer|
      members.each do |player|
        broadcast_replace_to self, viewer, target: ActionView::RecordIdentifier.dom_id(player),
                                           partial: 'players/player', locals: { player:, viewer: }
      end
    end
    scoreboard? ? broadcast_phase : broadcast_packs!
  end
end
