# What the Room does when a Player's presence changes. Away is a flag game logic reads; it never removes a Player.
# Presence changes are NOT Room activity (see Room::Activity).
module Room::Presence
  extend ActiveSupport::Concern

  # Called once each time a Player becomes Away. Under one Room lock: the Host role moves on if it was theirs, and the
  # phase ends early if nobody present is left to wait for. The gate broadcast goes out after commit.
  def player_went_away!(player)
    with_lock do
      hand_off_host!(from: player)
      finish_early_if_done!
    end
    ActiveRecord.after_all_transactions_commit { broadcast_start_gate! }
  end

  def present_players_count = players.here.count

  # The Start / Play again gate: at least MIN_PLAYERS present Players. Nil when open, else the reason.
  def present_players_gate_reason
    count = present_players_count
    "Need #{Room::MIN_PLAYERS} present Players, #{count} here" if count < Room::MIN_PLAYERS
  end

  # The dealt-in Players of the current Game who are present (Spectators have no seat).
  def present_game_players = current_game.game_players.where(player_id: players.here.select(:id))

  # Call after commit when presence or membership changed: re-sends each Player's gate (Start while Waiting, Play again
  # on the Scoreboard).
  def broadcast_start_gate!
    gate = if waiting? then %w[start_gate rooms/start_gate]
           elsif scoreboard? then %w[play_again_gate rooms/play_again_gate]
           end
    return unless gate

    players.each do |player|
      broadcast_replace_to self, player, target: gate.first, partial: gate.last, locals: { room: self, player: }
    end
  end
end
