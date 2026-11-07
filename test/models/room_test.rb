require 'test_helper'

# Room game operations are the main seam: tests call the operation and assert on
# what a Player could observe (phase, code, who is Host), not on rows or queries.
class RoomTest < ActiveSupport::TestCase
  test 'creating a Room makes a waiting Room with a 4-letter code and a Host Player' do
    room = Room.create_with_host(nickname: 'Ada', browser_token: 'tok-ada')

    assert_equal 'waiting', room.phase
    assert_match(/\A[A-Z]{4}\z/, room.code)
    assert_equal 'Ada', room.host.nickname
    assert room.host?(room.host)
    assert_equal [room.host], room.players.to_a
  end

  test 'a clash on a live code is retried with a new code' do
    Room.create_with_host(nickname: 'Ada', browser_token: 'a', codes: ['ABCD'].each)

    room = Room.create_with_host(nickname: 'Bob', browser_token: 'b', codes: %w[ABCD WXYZ].each)

    assert_equal 'WXYZ', room.code
  end

  test 'a code can be reused once its Room has expired' do
    old = Room.create_with_host(nickname: 'Ada', browser_token: 'a', codes: ['ABCD'].each)
    old.update!(expired_at: Time.current)

    room = Room.create_with_host(nickname: 'Bob', browser_token: 'b', codes: ['ABCD'].each)

    assert_equal 'ABCD', room.code
  end

  test 'two live Rooms can never share a code' do
    Room.create_with_host(nickname: 'Ada', browser_token: 'a', codes: ['ABCD'].each)

    assert_raises(ActiveRecord::RecordNotUnique) do
      Room.insert!({ code: 'ABCD', last_activity_at: Time.current })
    end
  end

  test 'nickname is required' do
    assert_raises(ActiveRecord::RecordInvalid) { Room.create_with_host(nickname: '', browser_token: 't') }
    assert_equal 0, Room.count
  end

  test 'nickname may be at most 16 characters' do
    assert Room.create_with_host(nickname: 'a' * 16, browser_token: 't').persisted?
    assert_raises(ActiveRecord::RecordInvalid) { Room.create_with_host(nickname: 'a' * 17, browser_token: 't') }
  end

  test 'nickname is unique per Room ignoring case, guaranteed by the database' do
    room = Room.create_with_host(nickname: 'Ada', browser_token: 'a')

    clash = room.players.build(nickname: 'ADA', browser_token: 'b', joined_at: Time.current)
    assert_not clash.valid?

    assert_raises(ActiveRecord::RecordNotUnique) do
      Player.insert!({ room_id: room.id, nickname: 'aDa', browser_token: 'b', joined_at: Time.current })
    end
  end

  test 'the same nickname is fine in a different Room' do
    Room.create_with_host(nickname: 'Ada', browser_token: 'a')

    assert Room.create_with_host(nickname: 'ada', browser_token: 'b').persisted?
  end

  test 'a Player is found by Room and browser token' do
    room = Room.create_with_host(nickname: 'Ada', browser_token: 'tok-ada')
    other = Room.create_with_host(nickname: 'Bob', browser_token: 'tok-bob')

    assert_equal room.host, room.player_for('tok-ada')
    assert_nil room.player_for('tok-bob')
    assert_nil room.player_for(nil)
    assert_equal other.host, other.player_for('tok-bob')
  end
end
