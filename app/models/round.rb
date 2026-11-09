class Round < ApplicationRecord
  belongs_to :game
  has_many :hands, dependent: :destroy
  has_many :memes, dependent: :destroy

  # Deal every game-player of the Game a fresh Hand. Called at the start of each Round's Captioning.
  def deal_hands! = Round::Dealer.new(self).deal!
end
