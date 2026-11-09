require 'test_helper'

# The placing rule: totals high to low, equal totals share a place, the next place skips (1, 1, 3).
class GamePlacingTest < ActiveSupport::TestCase
  setup do
    @room = room_with_players
    seed_templates(30)
    @room.start(by: @room.player_for('ada'))
    @game = @room.reload.current_game
  end

  def set_totals(*totals)
    %w[Ada Bob Cy].zip(totals).to_h.each do |nickname, total|
      @game.game_players.find_by(nickname:).update!(total:)
    end
  end

  def placed = @game.placed_game_players.map { |gp| [gp.place, gp.nickname, gp.total] }

  test 'orders by total, highest first, with sequential places when totals differ' do
    set_totals(3, 7, 0)

    assert_equal [[1, 'Bob', 7], [2, 'Ada', 3], [3, 'Cy', 0]], placed
  end

  test 'tied totals share a place and the next place skips' do
    set_totals(5, 5, 1)

    assert_equal [[1, 'Ada', 5], [1, 'Bob', 5], [3, 'Cy', 1]], placed
  end

  test 'a tie below the top shares the lower place' do
    set_totals(9, 2, 2)

    assert_equal [[1, 'Ada', 9], [2, 'Bob', 2], [2, 'Cy', 2]], placed
  end

  test 'negative totals place below zero' do
    set_totals(-4, 0, -1)

    assert_equal [[1, 'Bob', 0], [2, 'Cy', -1], [3, 'Ada', -4]], placed
  end

  test 'everyone tied is everyone first' do
    set_totals(2, 2, 2)

    assert_equal [[1, 'Ada', 2], [1, 'Bob', 2], [1, 'Cy', 2]], placed
  end
end
