# A Meme's vote closes early once every present eligible voter has voted. Eligible voters are the dealt-in
# Players other than the Meme's author; Spectators are never dealt in, and Away Players are not waited for
# (their missing Vote is scored as meh by Meme#score!, nothing is written for it).
# `vote_complete?` is one branch of Room::EarlyFinish#early_finish_due?.
module Room::VoteEarlyClose
  extend ActiveSupport::Concern

  # True while a Meme is under vote and every present eligible voter has voted. With nobody left to wait for
  # (no present voter) it is false, so the timers run the Game instead.
  def vote_complete?
    return false unless vote? && current_meme

    pending = present_game_players.where.not(id: current_meme.game_player_id)
    pending.any? && !pending.where.not(id: current_meme.votes.select(:game_player_id)).exists?
  end
end
