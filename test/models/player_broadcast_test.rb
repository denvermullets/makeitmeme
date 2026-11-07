require 'test_helper'
require 'turbo/broadcastable/test_helper'

class PlayerBroadcastTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @room = Room.create_with_host(nickname: 'Ada', browser_token: 'host-token')
    ActionCable.server.pubsub.clear
  end

  test 'a join appends the Player to the Room stream' do
    assert_turbo_stream_broadcasts @room, count: 1 do
      Room.join(code: @room.code, nickname: 'Bob', browser_token: 'bob')
    end
  end

  test 'a rejected join broadcasts nothing' do
    assert_no_turbo_stream_broadcasts @room do
      assert_raises(ActiveRecord::RecordInvalid) do
        Room.join(code: @room.code, nickname: 'ada', browser_token: 'x')
      end
    end
  end

  test 'a rolled-back join broadcasts nothing, because broadcasts go out after commit' do
    assert_no_turbo_stream_broadcasts @room do
      Player.transaction do
        @room.players.create!(nickname: 'Bob', browser_token: 'bob', joined_at: Time.current)
        raise ActiveRecord::Rollback
      end
    end
  end
end
