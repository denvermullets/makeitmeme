# Read model of a Game's final Scoreboard: one Row per game-player. Built only from the Game's own snapshot
# (game-players, Rounds, Memes; ADR 0002), so it never reads Players or Templates. Two queries whatever the
# Player count. Numbers come from cached columns; Votes are never re-tallied.
class Game::Scoreboard
  Row = Struct.new(:game_player_id, :place, :nickname, :total, :buddies_received, :memes_of_the_round, keyword_init: true)

  def initialize(game)
    @game = game
  end

  # Rows in order of place (ties share one, via Game#placed_game_players).
  def rows
    @rows ||= begin
      memes = Meme.joins(:round).where(rounds: { game_id: @game.id }).pluck(:game_player_id, :round_id, :points, :buddy_count)
      buddies = memes.group_by(&:first).transform_values { |own| own.sum(&:last) }
      honours = memes_of_the_round_counts(memes)
      @game.placed_game_players.map do |placing|
        seat = placing.game_player
        Row.new(game_player_id: seat.id, place: placing.place, nickname: seat.nickname, total: seat.total,
                buddies_received: buddies.fetch(seat.id, 0), memes_of_the_round: honours.fetch(seat.id, 0))
      end
    end
  end

  private

  # Per game-player, the Rounds where one of their Memes had the Round's top points (ties share, as Round#memes_of_the_round).
  def memes_of_the_round_counts(memes)
    memes.group_by { |_, round_id, _, _| round_id }.values.flat_map do |round_memes|
      top = round_memes.map { |m| m[2] }.max
      round_memes.select { |m| m[2] == top }.map(&:first).uniq
    end.tally
  end
end
