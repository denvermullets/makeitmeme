# The Room's one early-finish condition: a timed phase ends before its deadline once nobody present is left to
# wait for. `finish_early_if_done!` is evaluated under the Room lock and ends the phase through the same
# `advance!` path as the deadline, so a deadline job left behind finds a stale phase_seq and does nothing.
# Call it after anything that could complete the condition (a submission, a Vote, a Player going Away).
# Each phase adds its own `*_complete?` predicate to `early_finish_due?`.
module Room::EarlyFinish
  extend ActiveSupport::Concern

  def finish_early_if_done!
    with_lock do
      next false unless early_finish_due?

      advance!(from_seq: phase_seq)
    end
  end

  private

  def early_finish_due? = captioning_complete? || vote_complete?

  # Captioning: at least one present dealt-in Player, and every one of them has a Meme this Round.
  # Spectators have no GamePlayer; nobody present means the timer runs the Game.
  def captioning_complete?
    return false unless captioning? && current_game && current_round_number

    present_game_players.exists? && !present_game_players.where.not(id: round_meme_author_ids).exists?
  end

  def present_game_players = current_game.game_players.where(player_id: players.present.select(:id))

  def round_meme_author_ids
    Meme.joins(:round).where(rounds: { game_id: current_game_id, number: current_round_number }).select(:game_player_id)
  end
end
