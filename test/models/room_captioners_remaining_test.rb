require 'test_helper'

class RoomCaptionersRemainingTest < ActiveSupport::TestCase
  setup { @room = room_with_players }

  test 'is 0 with no Game under way' do
    assert_equal 0, @room.captioners_remaining
  end

  test 'counts the dealt-in Players without a Meme this Round' do
    seed_templates(30)
    @room.start(by: @room.player_for('ada'))
    assert_equal 3, @room.captioners_remaining

    submit_memes(@room, 'ada')
    assert_equal 2, @room.captioners_remaining
  end
end
