# Read model of a Game's final Scoreboard: one Row per game-player. Built only from the Game's own snapshot
# (game-players, Rounds, Memes; ADR 0002), so it never reads Players or Templates. Two queries whatever the
# Player count. Numbers come from cached columns; Votes are never re-tallied.
class Game::Scoreboard
  Row = Struct.new(:game_player_id, :place, :nickname, :total, :buddies_received, keyword_init: true)

  def initialize(game)
    @game = game
  end

  # Rows in order of place (ties share one, via Game#placed_game_players).
  def rows
    @rows ||= begin
      buddies = Meme.joins(:round).where(rounds: { game_id: @game.id }).group(:game_player_id).sum(:buddy_count)
      @game.placed_game_players.map do |placing|
        seat = placing.game_player
        Row.new(game_player_id: seat.id, place: placing.place, nickname: seat.nickname, total: seat.total,
                buddies_received: buddies.fetch(seat.id, 0))
      end
    end
  end
end
