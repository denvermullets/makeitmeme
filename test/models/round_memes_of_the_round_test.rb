require 'test_helper'

# Meme of the Round: derived from cached points, never stored; ties share it.
class RoundMemesOfTheRoundTest < ActiveSupport::TestCase
  setup do
    @room = room_with_players
    seed_templates(30)
    @room.start(by: @room.player_for('ada'))
    @round = @room.current_game.rounds.find_by!(number: 1)
  end

  def memes_with_points(*points)
    submit_memes(@room, 'ada', 'bob', 'cy')
    @round.memes.order(:id).zip(points).each { |meme, p| meme.update!(points: p) }
  end

  test 'a single top Meme is the Meme of the Round' do
    memes_with_points(1, 5, 2)

    assert_equal [@round.memes.order(:id).second], @round.memes_of_the_round.to_a
  end

  test 'tied top Memes all share it' do
    memes_with_points(4, 4, 1)

    assert_equal @round.memes.order(:id).first(2), @round.memes_of_the_round.order(:id).to_a
  end

  test 'a Round where every Meme is negative still has one' do
    memes_with_points(-3, -1, -5)

    assert_equal [@round.memes.order(:id).second], @round.memes_of_the_round.to_a
  end

  test 'a Round with no Memes has none' do
    assert_empty @round.memes_of_the_round
  end

  test 'it gives no points' do
    memes_with_points(1, 5, 2)

    assert_no_changes -> { @round.game.game_players.sum(:total) } do
      @round.memes_of_the_round.to_a
    end
  end
end
