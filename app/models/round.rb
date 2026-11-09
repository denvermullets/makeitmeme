class Round < ApplicationRecord
  belongs_to :game
  has_many :hands, dependent: :destroy
  has_many :memes, dependent: :destroy

  # The Round's top-scoring Memes by cached points (ties share; none when there are no Memes). An honour, not stored.
  def memes_of_the_round
    top = memes.maximum(:points)
    top ? memes.where(points: top) : memes.none
  end

  # Deal every game-player of the Game a fresh Hand. Called at the start of each Round's Captioning.
  def deal_hands! = Round::Dealer.new(self).deal!
end
