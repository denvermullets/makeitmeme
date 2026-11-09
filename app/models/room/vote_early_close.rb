# A Meme's vote closes early once every present eligible voter has voted. Eligible voters are the dealt-in
# Players other than the Meme's author; Spectators are never dealt in, and Away Players are not waited for
# (their missing Vote is scored as meh by Meme#score!, nothing is written for it).
module Room::VoteEarlyClose
  extend ActiveSupport::Concern

  # True while a Meme is under vote and every present eligible voter has voted. With nobody left to wait for
  # (no present voter) it is false, so the timers run the Game instead.
  def vote_complete?
    return false unless vote? && current_meme

    pending = present_voters.where.not(id: current_meme.game_player_id)
    pending.any? && !pending.where.not(id: current_meme.votes.select(:game_player_id)).exists?
  end

  # Advances the vote to its reveal when it is complete. Safe from any caller (after a Vote, when a Player
  # becomes Away); the left-behind deadline job then finds a stale phase_seq and does nothing.
  def finish_vote_early_if_done!
    with_lock { advance!(from_seq: phase_seq) if vote_complete? }
  end

  private

  def present_voters
    current_game.game_players.where(player_id: players.present.select(:id))
  end
end
