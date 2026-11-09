require 'test_helper'
require 'turbo/broadcastable/test_helper'

# Room game operation: joining with a nickname that already exists in the Room (trimmed, ignoring case).
class RoomTakeoverTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @room = room_with_players
    @bob = @room.player_for('bob')
  end

  def join(nickname, token)
    Room.join(code: @room.code, nickname:, browser_token: token)
  end

  test 'a present Players nickname is taken, ignoring case and surrounding spaces' do
    [' bob ', 'BOB', 'Bob'].each do |nickname|
      error = assert_raises(ActiveRecord::RecordInvalid) { join(nickname, 'new') }
      assert_includes error.record.errors.full_messages, 'That nickname is taken'
    end
    assert_equal @bob, @room.player_for('bob')
    assert_nil @room.player_for('new')
  end

  test 'an Away Players nickname is taken over: the token is rebound and the Player resumes' do
    @bob.update!(away_at: Time.current)

    player = join('  bOB ', 'phone-2')

    assert_equal @bob, player
    assert_equal @bob, @room.player_for('phone-2')
    assert_equal 'Bob', player.reload.nickname
    assert_equal 3, @room.players.count
  end

  test 'a takeover tells the Players stream to reload, so the old browser lands on the join form' do
    @bob.update!(away_at: Time.current)
    ActionCable.server.pubsub.clear

    assert_turbo_stream_broadcasts [@room, @bob], count: 1 do
      join('Bob', 'phone-2')
    end
  end

  test 'after a takeover the old browser matches no Player' do
    @bob.update!(away_at: Time.current)
    join('Bob', 'phone-2')

    assert_nil @room.player_for('bob')
  end

  test 'a takeover keeps the game-player row, score and Hand' do
    seed_templates(30)
    @room.start(by: @room.player_for('ada'))
    game_player = @room.current_game.game_player_for(@bob)
    game_player.update!(total: 7)
    hand = @room.hand_for(@bob).template_ids
    @bob.update!(away_at: Time.current)

    join('Bob', 'phone-2')

    taken = @room.player_for('phone-2')
    assert_equal game_player, @room.current_game.game_player_for(taken)
    assert_equal 7, game_player.reload.total
    assert_equal hand, @room.hand_for(taken).template_ids
  end

  test 'a browser that already holds a different Player cannot take over another' do
    @bob.update!(away_at: Time.current)

    player = join('Bob', 'cy')

    assert_equal @room.player_for('cy'), player
    assert_equal 'Cy', player.nickname
    assert_equal @bob, @room.player_for('bob')
  end

  test 'a takeover is not blocked by a full Room' do
    6.times { |i| join("P#{i}", "t#{i}") }
    @bob.update!(away_at: Time.current)

    assert_equal @bob, join('Bob', 'phone-2')
  end
end
