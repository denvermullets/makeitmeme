# What the Room does when a Player's presence changes. Away is a flag game logic reads; it never removes a Player.
# Presence changes are NOT Room activity (see Room::Activity).
module Room::Presence
  extend ActiveSupport::Concern

  # THE away-consequences hook: called once, after commit-worthy state is saved, each time a Player becomes Away.
  # Later tickets (Host handoff, early-finish re-checks) extend this method; keep it the single entry point.
  def player_went_away!(player); end
end
