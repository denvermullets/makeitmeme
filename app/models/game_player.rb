# A Player's seat in one Game: a nickname snapshot and the running total. Survives the Player (ADR 0002).
class GamePlayer < ApplicationRecord
  BUDDIES_PER_GAME = 2 # keep in step with the buddies_left column default

  belongs_to :game
  belongs_to :player, optional: true
  has_many :hands, dependent: :destroy
end
