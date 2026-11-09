# Deals a Round's Hands. Game-players are dealt one at a time in a random order; for each, the dealable Templates
# are sorted by a lexicographic key and the Hand is the first Hand::SIZE of them.
# No duplicate Template within a Hand holds by construction (the pool is distinct ids).
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
      round_dealt.merge(template_ids)
    end
    DealHistory.record!(room: @game.room, template_ids: round_dealt.to_a)
  end

  private

  # Smaller sorts first. Fields: [dealt to this game-player earlier this Game? (0 no, 1 yes),
  # dealt to any game-player earlier this Game? (0 no, 1 yes), in another Hand this Round? (0 no, 1 yes),
  # last dealt in this Room (never first, then oldest), random tiebreak].
  def sort_key(game_player, template_id)
    dealt_to_this_player = own_dealt(game_player).include?(template_id) ? 1 : 0
    dealt_to_anyone = game_dealt.include?(template_id) ? 1 : 0
    dealt_this_round = round_dealt.include?(template_id) ? 1 : 0
    [dealt_to_this_player, dealt_to_anyone, dealt_this_round, last_dealt_at(template_id), rand]
  end

  # Never dealt in this Room sorts first (0), then oldest first. Read before this deal is recorded.
  def last_dealt_at(template_id)
    @last_dealt_at ||= DealHistory.where(room_id: @game.room_id).pluck(:template_id, :last_dealt_at).to_h
    @last_dealt_at[template_id]&.to_f || -Float::INFINITY
  end

  # Grows as each Hand of this Round is dealt.
  def round_dealt
    @round_dealt ||= Set.new
  end

  def game_dealt
    @game_dealt ||= earlier_template_ids(Hand.all)
  end

  def own_dealt(game_player)
    @own_dealt ||= {}
    @own_dealt[game_player.id] ||= earlier_template_ids(Hand.where(game_player_id: game_player.id))
  end

  # Template ids in the given Hands that were dealt in this Game's earlier Rounds.
  def earlier_template_ids(hands)
    hands.joins(:round).where(rounds: { game_id: @game.id }).where.not(round_id: @round.id)
         .pluck(:template_ids).flatten.to_set
  end
end
