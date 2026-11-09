require 'test_helper'
require 'turbo/broadcastable/test_helper'

class RoomPackBroadcastTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @room = room_with_players
    @host = @room.player_for('ada')
    @classics = Pack.classics
    @extra = Pack.create!(name: 'Extra')
    seed_templates(6)
    Array.new(5) { |i| Template.create!(memegen_id: "x#{i}", name: "X#{i}", text_boxes: [], pack: @extra) }
    ActionCable.server.pubsub.clear
  end

  def fragment_for(player, target)
    streams = capture_turbo_stream_broadcasts([@room, player])
    streams.map { |s| Nokogiri::HTML.fragment(s.to_html) }.find { |f| f.at_css("##{target}") }
  end

  test 'a toggle sends every Player their own Pack list on their own stream, after commit' do
    @room.toggle_pack(pack: @extra, by: @host, on: false)

    @room.players.each do |player|
      list = fragment_for(player, 'pack_list')
      assert list, "#{player.nickname} got no pack list"
      assert_equal 'false', list.at_css("[data-pack='#{@extra.id}']")['data-pack-on']
      assert_equal 'true', list.at_css("[data-pack='#{@classics.id}']")['data-pack-on']
      assert_equal @host == player, list.css('button').any?
    end
  end

  test 'the Start gate follows the toggle: only the Host gets a button, disabled below 10' do
    @room.toggle_pack(pack: @extra, by: @host, on: false)

    gate = fragment_for(@host, 'start_gate')
    assert gate.at_css('button[disabled]')
    assert gate.at_css('#start-gate-reason')
    assert_nil fragment_for(@room.player_for('bob'), 'start_gate').at_css('button')

    ActionCable.server.pubsub.clear
    @room.toggle_pack(pack: @extra, by: @host, on: true)
    gate = fragment_for(@host, 'start_gate')
    assert gate.at_css('button')
    assert_nil gate.at_css('button[disabled]')
    assert_nil gate.at_css('#start-gate-reason')
  end

  test 'the Start gate says how many Players are present and follows presence live' do
    @room.player_for('cy').update!(away_at: Time.current)
    @room.broadcast_packs!

    gate = fragment_for(@host, 'start_gate')
    assert gate.at_css('button[disabled]')
    assert_equal 'Need 3 present Players, 2 here', gate.at_css('#start-gate-reason').text.strip

    ActionCable.server.pubsub.clear
    @room.player_for('cy').connected!
    assert_nil fragment_for(@host, 'start_gate').at_css('button[disabled]')
  end

  test 'a refused toggle broadcasts nothing' do
    assert_no_turbo_stream_broadcasts @room do
      assert_raises(ActiveRecord::RecordInvalid) { @room.toggle_pack(pack: @extra, by: @room.player_for('bob')) }
    end
  end
end
