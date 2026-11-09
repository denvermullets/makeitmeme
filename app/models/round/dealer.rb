# Deals a Round's Hands. Game-players are dealt one at a time in a random order; for each, the dealable Templates
# are sorted by a lexicographic key and the Hand is the first Hand::SIZE of them. Later dealing rules add fields
# to `sort_key`. No duplicate Template within a Hand holds by construction (the pool is distinct ids).
class Round::Dealer
  def initialize(round)
    @round = round
    @game = round.game
  end

  def deal!
    pool = Template.dealable_for(@game.room).pluck(:id)
    @game.game_players.to_a.shuffle.each do |game_player|
      template_ids = pool.sort_by { |id| sort_key(game_player, id) }.first(Hand::SIZE)
      @round.hands.create!(game_player:, template_ids:)
    end
  end

  private

  # Smaller sorts first. Fields: [dealt to this game-player earlier this Game? (0 no, 1 yes), random tiebreak].
  def sort_key(game_player, template_id)
    [own_dealt(game_player).include?(template_id) ? 1 : 0, rand]
  end

  def own_dealt(game_player)
    @own_dealt ||= {}
    @own_dealt[game_player.id] ||= Hand.joins(:round)
                                       .where(rounds: { game_id: @game.id }, game_player_id: game_player.id)
                                       .where.not(round_id: @round.id).pluck(:template_ids).flatten.to_set
  end
end
