require 'test_helper'
require 'turbo/broadcastable/test_helper'

# Story 63: Library and Pack changes re-broadcast the Pack list (and Start gate in Waiting) to every open Room.
class LibraryPackBroadcastTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @room = room_with_players
    @ada = @room.player_for('ada')
    @template = seed_templates(2).first
    ActionCable.server.pubsub.clear
  end

  def list_for(player, room: @room, target: 'pack_list')
    streams = capture_turbo_stream_broadcasts([room, player])
    streams.map { |s| Nokogiri::HTML.fragment(s.to_html) }.find { |f| f.at_css("##{target}") }
  end

  def assert_broadcast_to_room
    yield
    @room.players.each { |player| assert list_for(player), "#{player.nickname} got no pack list" }
  end

  def count_for(pack)
    list_for(@ada).at_css("[data-pack='#{pack.id}'] .pack-count").text.strip
  end

  test 'creating a Pack re-broadcasts the list with the new Pack, after commit' do
    pack = nil
    assert_broadcast_to_room { pack = Pack.create!(name: 'Fresh') }
    assert list_for(@ada).at_css("[data-pack='#{pack.id}']")
  end

  test 'renaming a Pack re-broadcasts' do
    pack = Pack.create!(name: 'Old')
    ActionCable.server.pubsub.clear
    assert_broadcast_to_room { pack.update!(name: 'New') }
    assert_includes list_for(@ada).text, 'New'
  end

  test 'destroying a Pack re-broadcasts without it' do
    pack = Pack.create!(name: 'Doomed')
    ActionCable.server.pubsub.clear
    assert_broadcast_to_room { pack.destroy! }
    assert_nil list_for(@ada).at_css("[data-pack='#{pack.id}']")
  end

  test 'hiding a Template updates the count and the Start gate' do
    pack = @template.pack
    before = Template.not_hidden.where(pack:).count
    assert_broadcast_to_room { @template.hide! }
    assert_equal (before - 1).to_s, count_for(pack)
    assert list_for(@ada, target: 'start_gate')
  end

  test 'unhiding, moving, creating and deleting a Template each re-broadcast' do
    @template.hide!
    other = Pack.create!(name: 'Other')
    ActionCable.server.pubsub.clear

    assert_broadcast_to_room { @template.unhide! }
    ActionCable.server.pubsub.clear
    assert_broadcast_to_room { @template.update!(pack: other) }
    assert_equal '1', count_for(other)
    ActionCable.server.pubsub.clear
    assert_broadcast_to_room { Template.create!(memegen_id: 'new1', name: 'New', text_boxes: [], pack: other) }
    assert_equal '2', count_for(other)
    ActionCable.server.pubsub.clear
    assert_broadcast_to_room { @template.destroy! }
    assert_equal '1', count_for(other)
  end

  test 'renaming a Template does not broadcast' do
    assert_no_turbo_stream_broadcasts @room do
      @template.update!(name: 'Different')
    end
  end

  test 'the Scoreboard gets the Pack list but not the Start gate' do
    @room.update_column(:phase, 'scoreboard')
    ActionCable.server.pubsub.clear
    @template.hide!
    assert list_for(@ada)
    assert_nil list_for(@ada, target: 'start_gate')
  end

  test 'Rooms mid-Game are left alone' do
    @room.update_column(:phase, 'captioning')
    ActionCable.server.pubsub.clear

    assert_no_turbo_stream_broadcasts @room do
      @template.hide!
    end
  end

  test 'nothing is sent before commit' do
    Template.transaction do
      @template.hide!
      assert_nil list_for(@ada)
    end
    assert list_for(@ada)
  end
end
