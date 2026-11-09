# Read model of a Game's final Scoreboard: one Row per game-player. Built only from the Game's own snapshot
# (game-players, Rounds, Memes; ADR 0002), so it never reads Players or Templates. Three queries whatever the
# Player count. Numbers come from cached columns; Votes are never re-tallied.
class Game::Scoreboard
  # round_points: [[round_number, points or nil], ...] in Round order; nil means no Meme that Round (not 0).
  Row = Struct.new(:game_player_id, :place, :nickname, :total, :buddies_received, :memes_of_the_round, :round_points,
                   keyword_init: true)

  def initialize(game)
    @game = game
  end

  # Rows in order of place (ties share one, via Game#placed_game_players).
  def rows
    @rows ||= begin
      memes = Meme.joins(:round).where(rounds: { game_id: @game.id })
                  .pluck(:game_player_id, :round_id, 'rounds.number', :points, :buddy_count)
      buddies = memes.group_by(&:first).transform_values { |own| own.sum(&:last) }
      honours = memes_of_the_round_counts(memes)
      points = memes.to_h { |seat_id, _, number, pts, _| [[seat_id, number], pts] }
      numbers = @game.rounds.order(:number).pluck(:number)
      @game.placed_game_players.map do |placing|
        seat = placing.game_player
        Row.new(game_player_id: seat.id, place: placing.place, nickname: seat.nickname, total: seat.total,
                buddies_received: buddies.fetch(seat.id, 0), memes_of_the_round: honours.fetch(seat.id, 0),
                round_points: numbers.map { |n| [n, points[[seat.id, n]]] })
      end
    end
  end

  private

  # Per game-player, the Rounds where one of their Memes had the Round's top points (ties share, as Round#memes_of_the_round).
  def memes_of_the_round_counts(memes)
    memes.group_by { |_, round_id, *| round_id }.values.flat_map do |round_memes|
      top = round_memes.map { |m| m[3] }.max
      round_memes.select { |m| m[3] == top }.map(&:first).uniq
    end.tally
  end
end
