class Round < ApplicationRecord
  belongs_to :game
  has_many :hands, dependent: :destroy

  # Deal every game-player of the Game a fresh Hand. Called at the start of each Round's Captioning.
  def deal_hands!
    template_ids = Template.pluck(:id)
    game.game_players.each { |game_player| hands.create!(game_player:, template_ids: template_ids.sample(Hand::SIZE)) }
  end
end
