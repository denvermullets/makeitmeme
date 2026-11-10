# Read model of a Game's final Scoreboard: one Row per game-player. Built only from the Game's own snapshot
# (game-players, Rounds, Memes; ADR 0002), so it never reads Players or Templates. Three queries whatever the
# Player count. Numbers come from cached columns; Votes are never re-tallied.
class Game::Scoreboard
  # round_points: [[round_number, points or nil], ...] in Round order; nil means no Meme that Round (not 0).
  # missed_votes / unused_buddies: the penalties already taken off the total (GamePlayer).
  Row = Struct.new(:game_player_id, :place, :nickname, :total, :buddies_received, :memes_of_the_round, :round_points,
                   :missed_votes, :unused_buddies, keyword_init: true)

  # One Meme's cached numbers, plucked once and reused for Buddies, honours and per-Round points.
  # buddy_count here counts Meme Buddy Redux too: both are Buddies the Meme received.
  MemeFact = Struct.new(:game_player_id, :round_id, :round_number, :points, :buddy_count)

  def initialize(game)
    @game = game
  end

  # Rows in order of place (ties share one, via Game#placed_game_players).
  def rows
    @rows ||= begin
      memes = Meme.joins(:round).where(rounds: { game_id: @game.id })
                  .pluck(:game_player_id, :round_id, 'rounds.number', :points, :buddy_count, :redux_count)
                  .map { |*values, buddy, redux| MemeFact.new(*values, buddy + redux) }
      buddies = memes.group_by(&:game_player_id).transform_values { |own| own.sum(&:buddy_count) }
      honours = memes_of_the_round_counts(memes)
      points = memes.to_h { |meme| [[meme.game_player_id, meme.round_number], meme.points] }
      numbers = @game.rounds.order(:number).pluck(:number)
      @game.placed_game_players.map do |placing|
        seat = placing.game_player
        Row.new(game_player_id: seat.id, place: placing.place, nickname: seat.nickname, total: seat.total,
                buddies_received: buddies.fetch(seat.id, 0), memes_of_the_round: honours.fetch(seat.id, 0),
                round_points: numbers.map { |n| [n, points[[seat.id, n]]] }, missed_votes: seat.missed_votes,
                unused_buddies: seat.unused_buddies)
      end
    end
  end

  private

  # Per game-player, the Rounds where one of their Memes was a Meme of the Round (Round.top_scoring).
  def memes_of_the_round_counts(memes)
    memes.group_by(&:round_id).values.flat_map do |round_memes|
      Round.top_scoring(round_memes).map(&:game_player_id).uniq
    end.tally
  end
end
