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
      editor = Nokogiri::HTML.fragment(streams.first.to_html).at_css('[data-controller="meme-editor"]')
      dealt = JSON.parse(editor['data-meme-editor-hand-value']).map { |template| template['id'] }
      assert_equal @room.hand_for(player).template_ids, dealt
    end
  end

  test 'a refused start broadcasts nothing' do
    assert_no_turbo_stream_broadcasts @room do
      assert_raises(ActiveRecord::RecordInvalid) { @room.start(by: @room.player_for('bob')) }
    end
  end
end
