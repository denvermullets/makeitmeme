require 'test_helper'
require 'turbo/broadcastable/test_helper'

class RoomStartBroadcastTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @room = room_with_players
    @host = @room.player_for('ada')
    seed_templates(30)
    ActionCable.server.pubsub.clear
  end

  test 'starting switches the Room stream to Captioning' do
    assert_turbo_stream_broadcasts @room, count: 1 do
      @room.start(by: @host)
    end
  end

  test 'each Player gets their own Hand on their own stream, and only that Hand' do
    @room.start(by: @host)

    @room.players.each do |player|
      streams = capture_turbo_stream_broadcasts([@room, player])
      assert_equal 1, streams.size
      html = streams.first.to_html
      own = @room.hand_for(player).template_ids
      own.each { |id| assert_includes html, "template_#{id}\"" }
      (Template.pluck(:id) - own).each { |id| assert_not_includes html, "template_#{id}\"" }
    end
  end

  test 'a refused start broadcasts nothing' do
    assert_no_turbo_stream_broadcasts @room do
      assert_raises(ActiveRecord::RecordInvalid) { @room.start(by: @room.player_for('bob')) }
    end
  end
end
