# The vote flow: after Captioning each of the Round's Memes in turn gets a vote. Nothing is scored on screen until
# the Round's results (the Standings phase), so a Meme's points stay hidden while the Round is being voted on.
module Room::Voting
  extend ActiveSupport::Concern

  included do
    belongs_to :current_meme, class_name: 'Meme', optional: true, inverse_of: false
  end

  # Room game operation: a Player casts their Vote on the Meme under vote. A tap is final.
  # Raises ActiveRecord::RecordInvalid unless it is the vote phase, the caller is in the Game, `meme_id`
  # is the current Meme, it is not their own, they have not voted yet and `kind` is up, meh, down, buddy or redux.
  # A Buddy also needs one left; it is spent in the same transaction as the Vote. A Redux needs the last Meme of
  # the Game and no Buddies left (see `redux_offered_to?`).
  def cast_vote(by:, meme_id:, kind:)
    with_lock do
      reject!('Voting is closed') if !vote? || closed?
      voter = game_player_for(by) || reject!('You are not in this Game')
      validate_vote!(voter, meme_id, kind)

      record_vote(voter, kind)
    end
  end

  # The Player's seat in the current Game, or nil (not dealt in, or no Game under way).
  def game_player_for(player)
    current_game&.game_player_for(player)
  end

  # The Player's own Vote on the Meme under vote, or nil.
  def vote_by(player)
    current_meme&.vote_by(game_player_for(player))
  end

  # Entry step: the Round's Memes are in. Shuffle them into an order and vote on the first;
  # with none, move straight on to the Round's results. Call under the Room row lock.
  def finish_captioning!
    memes = current_round.memes.to_a.shuffle
    memes.each_with_index { |meme, index| meme.update!(position: index) }
    memes.empty? ? enter_standings! : enter_vote!(memes.first)
  end

  # Entry step: everyone votes on this Meme, for `phase_seconds[:vote]`.
  def enter_vote!(meme)
    enter_phase!(:vote, current_meme: meme)
  end

  # Vote's next step: score the Meme just voted on (its counts and points, the maker's total and any missed-Vote
  # penalties; nothing is shown yet), then vote on the next Meme or, past the last one, show the Round's results.
  # Call under the Room row lock, inside the phase_seq-guarded advance, so a Meme is never scored twice.
  def finish_vote!
    current_meme.score!(eligible_voters: current_game.game_players.count - 1)
    following = current_round.memes.find_by(position: current_meme.position + 1)
    following ? enter_vote!(following) : enter_standings!
  end

  # The Meme under vote is the last one of the Game: Round 3 and nothing after it.
  def final_meme?
    return false unless vote? && current_meme && current_round_number == Room::ROUNDS_PER_GAME

    !current_round.memes.exists?(['position > ?', current_meme.position])
  end

  # Meme Buddy Redux is on offer to this voter: the last Meme of the Game and their Buddies are all spent.
  def redux_offered_to?(voter) = voter.buddies_left.zero? && final_meme?

  # The current Round's Memes in voting order, with their makers and images, for the Round's results.
  def round_results
    return Meme.none unless current_game && current_round_number

    current_round.memes.includes(:game_player, image_attachment: :blob).order(:position, :id)
  end

  # The current Round's Meme(s) of the Round, with their makers, or none outside a Game.
  def memes_of_the_round
    return unless current_game

    round = current_game.rounds.find_by(number: current_round_number)
    round&.memes_of_the_round&.includes(:game_player)
  end

  private

  # Raises unless this Voter may cast a `kind` Vote on `meme_id` right now.
  def validate_vote!(voter, meme_id, kind)
    reject!('That is not the Meme being voted on') unless meme_id.to_i == current_meme_id
    reject!('You cannot vote on your own Meme') if current_meme.game_player_id == voter.id
    reject!('You already voted') if current_meme.vote_by(voter)
    validate_buddy!(voter, kind)
  end

  # Raises unless this voter may spend a Buddy or a Meme Buddy Redux, when `kind` is one.
  def validate_buddy!(voter, kind)
    reject!('You have no Buddies left') if buddy?(kind) && voter.buddies_left.zero?
    reject!('Meme Buddy Redux is not on offer') if kind.to_s == 'redux' && !redux_offered_to?(voter)
  end

  # Stores the Vote, then closes the vote early when it was the last one awaited.
  def record_vote(voter, kind)
    current_meme.votes.create!(game_player: voter, kind:).tap do
      voter.decrement!(:buddies_left) if buddy?(kind)
      finish_early_if_done!
    end
  end

  def buddy?(kind) = kind.to_s == 'buddy'

  def current_round = current_game.rounds.find_by!(number: current_round_number)
end
