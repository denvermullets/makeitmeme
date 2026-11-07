require 'test_helper'

# Room game operation: join a live Room by code.
class RoomJoinTest < ActiveSupport::TestCase
  setup do
    @room = Room.create_with_host(nickname: 'Ada', browser_token: 'host-token')
  end

  test 'joining with a valid code and nickname adds a Player to the Room' do
    player = Room.join(code: @room.code, nickname: 'Bob', browser_token: 'bob-token')

    assert_equal 'Bob', player.nickname
    assert_equal %w[Ada Bob], @room.players.order(:joined_at, :id).map(&:nickname)
    assert_equal player, @room.player_for('bob-token')
  end

  test 'the code is matched ignoring case' do
    player = Room.join(code: @room.code.downcase, nickname: 'Bob', browser_token: 'bob-token')

    assert_equal @room, player.room
  end

  test 'a browser that is already a Player gets its own Player back' do
    first = Room.join(code: @room.code, nickname: 'Bob', browser_token: 'bob-token')
    again = Room.join(code: @room.code, nickname: 'Other', browser_token: 'bob-token')

    assert_equal first, again
    assert_equal 2, @room.players.count
  end

  test 'an unknown code is rejected with a clear message' do
    error = assert_raises(ActiveRecord::RecordInvalid) do
      Room.join(code: 'ZZZZ', nickname: 'Bob', browser_token: 't')
    end
    assert_includes error.record.errors.full_messages, 'No live Room with that code'
  end

  test 'an expired Room cannot be joined' do
    @room.update!(expired_at: Time.current)

    assert_raises(ActiveRecord::RecordInvalid) do
      Room.join(code: @room.code, nickname: 'Bob', browser_token: 't')
    end
    assert_equal 1, @room.players.count
  end

  test 'a nickname taken ignoring case is rejected' do
    error = assert_raises(ActiveRecord::RecordInvalid) do
      Room.join(code: @room.code, nickname: 'ADA', browser_token: 't')
    end
    assert_includes error.record.errors.full_messages, 'Nickname has already been taken'
  end

  test 'an empty nickname is rejected' do
    assert_raises(ActiveRecord::RecordInvalid) do
      Room.join(code: @room.code, nickname: '  ', browser_token: 't')
    end
  end

  test 'a nickname over 16 characters is rejected' do
    assert_raises(ActiveRecord::RecordInvalid) do
      Room.join(code: @room.code, nickname: 'x' * 17, browser_token: 't')
    end
    assert_equal 1, @room.players.count
  end

  test 'a Room with 10 Players is full' do
    9.times { |i| Room.join(code: @room.code, nickname: "P#{i}", browser_token: "t#{i}") }
    assert_equal 10, @room.players.count

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Room.join(code: @room.code, nickname: 'Late', browser_token: 'late')
    end
    assert_includes error.record.errors.full_messages, 'Room is full (10 Players)'
    assert_equal 10, @room.players.count
  end
end
