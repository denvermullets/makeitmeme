# One run of three Rounds within a Room. Keeps its own copies of everything its Recap shows (ADR 0002).
class Game < ApplicationRecord
  belongs_to :room
  has_many :game_players, dependent: :destroy
  has_many :rounds, dependent: :destroy

  has_secure_token :recap_token

  enum :status, { in_progress: 'in_progress', finished: 'finished' }, default: :in_progress

  # The Player's seat in this Game, or nil.
  def game_player_for(player)
    game_players.find_by(player_id: player.id) if player
  end
end
