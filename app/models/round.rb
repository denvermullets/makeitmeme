class Round < ApplicationRecord
  belongs_to :game
  has_many :hands, dependent: :destroy
  has_many :memes, dependent: :destroy

  # The one Meme of the Round rule: of already-loaded memes (anything with `points`), those with the top cached
  # points. Ties share; none when there are no memes. An honour, not stored.
  def self.top_scoring(memes)
    top = memes.map(&:points).max
    memes.select { |meme| meme.points == top }
  end

  # The Round's Memes of the Round as a relation (see Round.top_scoring).
  def memes_of_the_round
    memes.where(id: Round.top_scoring(memes.select(:id, :points)).map(&:id))
  end

  # Deal every game-player of the Game a fresh Hand. Called at the start of each Round's Captioning.
  def deal_hands! = Round::Dealer.new(self).deal!
end
