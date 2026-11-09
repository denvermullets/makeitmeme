# One run of three Rounds within a Room. Keeps its own copies of everything its Recap shows (ADR 0002).
class Game < ApplicationRecord
  belongs_to :room
  has_many :game_players, dependent: :destroy
  has_many :rounds, dependent: :destroy

  has_secure_token :recap_token

  enum :status, { in_progress: 'in_progress', finished: 'finished' }, default: :in_progress

  Placing = Struct.new(:game_player, :place)

  # A Placing per game-player, highest total first. Place is 1 + the number with a strictly higher total,
  # so ties share a place (1, 1, 3). Reads cached totals only.
  def placed_game_players
    ordered = game_players.order(total: :desc, id: :asc).to_a
    ordered.map do |game_player|
      Placing.new(game_player, ordered.count { |other| other.total > game_player.total } + 1)
    end
  end

  # The Player's seat in this Game, or nil.
  def game_player_for(player)
    game_players.find_by(player_id: player.id) if player
  end
end
