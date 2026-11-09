# What the Room does when a Player's presence changes. Away is a flag game logic reads; it never removes a Player.
# Presence changes are NOT Room activity (see Room::Activity).
module Room::Presence
  extend ActiveSupport::Concern

  # THE away-consequences hook: called once, after commit-worthy state is saved, each time a Player becomes Away.
  # Later tickets (Host handoff, early-finish re-checks) extend this method; keep it the single entry point.
  def player_went_away!(player)
    hand_off_host!(from: player)
    broadcast_start_gate!
  end

  def present_players_count = players.present.count

  # The Start / Play again gate: at least MIN_PLAYERS present Players. Nil when open, else the reason.
  def present_players_gate_reason
    count = present_players_count
    "Need #{Room::MIN_PLAYERS} present Players, #{count} here" if count < Room::MIN_PLAYERS
  end

  # Call after commit when presence or membership changed: re-sends each Player's Start gate while Waiting.
  def broadcast_start_gate!
    return unless waiting?

    players.each do |player|
      broadcast_replace_to self, player, target: 'start_gate', partial: 'rooms/start_gate',
                                         locals: { room: self, player: }
    end
  end
end
