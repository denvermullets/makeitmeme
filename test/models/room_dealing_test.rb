require 'test_helper'

# Dealing: Hands follow the ordered rules, observed through the Room's start and Round advances.
class RoomDealingTest < ActiveSupport::TestCase
  # Starts a Game and advances through all three Rounds' Captioning; returns each Round's Hands.
  def play_three_rounds(room)
    room.start(by: room.host)
    hands = []
    3.times do
      hands << room.current_game.rounds.find_by(number: room.current_round_number).hands.to_a
      room.advance!
    end
    hands
  end

  def ids_by_player(hands_per_round)
    hands_per_round.flatten.group_by(&:game_player_id).transform_values do |hands|
      hands.map(&:template_ids)
    end
  end

  test 'no Hand contains the same Template twice, at any pool size' do
    [Hand::SIZE, 12, 30].each do |size|
      Template.destroy_all
      seed_templates(size)
      room = room_with_players

      play_three_rounds(room).flatten.each do |hand|
        assert_equal Hand::SIZE, hand.template_ids.size
        assert_equal hand.template_ids.uniq, hand.template_ids, "duplicate at pool size #{size}"
      end
    end
  end

  test 'a Player is never dealt the same Template in two Rounds while the pool allows it' do
    seed_templates(30)
    room = room_with_players

    ids_by_player(play_three_rounds(room)).each_value do |hands|
      all = hands.flatten
      assert_equal all.uniq.size, all.size
    end
  end

  test 'with exactly 10 dealable Templates the Game still runs all three Rounds' do
    seed_templates(Hand::SIZE)
    room = room_with_players

    hands = play_three_rounds(room)

    assert_equal 3, hands.size
    assert(hands.all? { |round_hands| round_hands.size == 3 })
    assert room.reload.scoreboard?
  end

  test 'hidden Templates and Templates in Packs that are off are never dealt' do
    seed_templates(30)
    hidden = seed_templates(5)
    hidden.each { |template| template.update!(hidden_at: Time.current) }
    room = room_with_players

    play_three_rounds(room).flatten.each do |hand|
      assert_empty hand.template_ids & hidden.map(&:id)
    end
  end

  test 'a dealt Hand does not change during its Round' do
    seed_templates(30)
    room = room_with_players
    room.start(by: room.host)
    before = room.hand_for(room.host).template_ids.dup

    room.reload
    assert_equal before, room.hand_for(room.host).reload.template_ids
  end

  test 'with 90 dealable Templates and 3 Players no Template appears in more than one Round' do
    seed_templates(90)
    room = room_with_players

    hands_per_round = play_three_rounds(room)
    all = hands_per_round.flatten.flat_map(&:template_ids)

    assert_equal all.uniq.size, all.size
  end

  test 'with 30 dealable Templates and 3 Players Round 1 Hands share no Template' do
    seed_templates(30)
    room = room_with_players
    room.start(by: room.host)

    ids = room.current_game.rounds.find_by(number: 1).hands.flat_map(&:template_ids)

    assert_equal 30, ids.size
    assert_equal ids.uniq.size, ids.size
  end

  test 'with 15 dealable Templates Round 1 Hands overlap, stay distinct, and use every Template' do
    seed_templates(15)
    room = room_with_players
    room.start(by: room.host)

    hands = room.current_game.rounds.find_by(number: 1).hands.to_a
    ids = hands.flat_map(&:template_ids)

    hands.each { |hand| assert_equal hand.template_ids.uniq, hand.template_ids }
    assert_operator ids.uniq.size, :<, ids.size
    assert_equal Template.dealable_for(room).pluck(:id).sort, ids.uniq.sort
  end

  test 'when short a Player takes Templates others hold this Round before ones they had earlier' do
    seed_templates(15)
    room = room_with_players
    room.start(by: room.host)
    room.advance!
    game = room.current_game
    round_one = game.rounds.find_by(number: 1).hands.index_by(&:game_player_id)

    game.rounds.find_by(number: 2).hands.each do |hand|
      not_own = Template.dealable_for(room).pluck(:id) - round_one[hand.game_player_id].template_ids
      assert_empty not_own - hand.template_ids
    end
  end

  test 'in Round 2 with room for it Hands in the Round do not overlap' do
    seed_templates(60)
    room = room_with_players
    room.start(by: room.host)
    room.advance!

    ids = room.current_game.rounds.find_by(number: 2).hands.flat_map(&:template_ids)

    assert_equal ids.uniq.size, ids.size
  end

  test 'with 30 dealable Templates later Rounds reuse Templates others had, never ones the Player had' do
    seed_templates(30)
    room = room_with_players

    hands = play_three_rounds(room)

    ids_by_player(hands).each_value do |player_hands|
      assert_equal player_hands.flatten.uniq.size, player_hands.flatten.size
    end
    assert_operator hands.flatten.flat_map(&:template_ids).uniq.size, :<=, 30
    assert_operator hands[1..].flatten.flat_map(&:template_ids).size, :>, 0
  end

  test 'a Template nobody was dealt earlier in the Game is dealt before one someone was' do
    seed_templates(40)
    room = room_with_players
    room.start(by: room.host)
    room.advance!
    dealt_round_one = room.current_game.rounds.find_by(number: 1).hands.flat_map(&:template_ids).uniq
    fresh_count = Template.dealable_for(room).count - dealt_round_one.size

    round_two = room.current_game.rounds.find_by(number: 2).hands
    round_two.each do |hand|
      assert_equal [fresh_count, Hand::SIZE].min, (hand.template_ids - dealt_round_one).size
    end
  end
end
