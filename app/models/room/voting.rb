# The vote/reveal flow: after Captioning each of the Round's Memes in turn gets a vote, then a reveal.
module Room::Voting
  extend ActiveSupport::Concern

  included do
    belongs_to :current_meme, class_name: 'Meme', optional: true, inverse_of: false
  end

  # Room game operation: a Player casts their Vote on the Meme under vote. A tap is final.
  # Raises ActiveRecord::RecordInvalid unless it is the vote phase, the caller is in the Game, `meme_id`
  # is the current Meme, it is not their own, they have not voted yet and `kind` is up, meh or down.
  def cast_vote(by:, meme_id:, kind:)
    with_lock do
      reject!('Voting is closed') if !vote? || closed?
      voter = game_player_for(by) || reject!('You are not in this Game')
      reject!('That is not the Meme being voted on') unless meme_id.to_i == current_meme_id
      reject!('You cannot vote on your own Meme') if current_meme.game_player_id == voter.id
      reject!('You already voted') if current_meme.vote_by(voter)

      current_meme.votes.create!(game_player: voter, kind:)
    end
  end

  # The Player's seat in the current Game, or nil (not dealt in, or no Game under way).
  def game_player_for(player)
    current_game&.game_player_for(player)
  end

  # How many Players in the Game have not yet submitted a Meme this Round.
  def captioners_remaining
    current_game.game_players.count - current_round.memes.count
  end

  # The Player's own Vote on the Meme under vote, or nil.
  def vote_by(player)
    current_meme&.vote_by(game_player_for(player))
  end

  # Entry step: the Round's Memes are in. Shuffle them into an order and vote on the first;
  # with none, move straight on. Call under the Room row lock.
  def finish_captioning!
    memes = current_round.memes.to_a.shuffle
    memes.each_with_index { |meme, index| meme.update!(position: index) }
    memes.empty? ? enter_next_round_or_scoreboard! : enter_vote!(memes.first)
  end

  # Entry step: everyone votes on this Meme, for `phase_seconds[:vote]`.
  def enter_vote!(meme)
    enter_phase!(:vote, current_meme: meme)
  end

  # Entry step: the Meme is shown again after its vote, with its score. Caches the Meme's up/meh/down counts
  # and points from its Vote rows and adds the points to the maker's total. Call under the Room row lock,
  # inside the phase_seq-guarded advance, so a Meme is never scored twice.
  def enter_reveal!
    current_meme.score!(eligible_voters: current_game.game_players.count - 1)
    enter_phase!(:reveal)
  end

  # After a reveal: the next Meme's vote, or past the last Meme the next Round or the Scoreboard.
  def finish_reveal!
    following = current_round.memes.find_by(position: current_meme.position + 1)
    following ? enter_vote!(following) : enter_next_round_or_scoreboard!
  end

  private

  def current_round = current_game.rounds.find_by!(number: current_round_number)
end
