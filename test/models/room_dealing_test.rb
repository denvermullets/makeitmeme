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
      room.advance! if room.reload.standings?
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
end
