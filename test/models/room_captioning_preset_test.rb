require 'test_helper'
require 'turbo/broadcastable/test_helper'

class RoomCaptioningPresetTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @room = room_with_players
    @host = @room.host
    seed_templates(12)
    @original_seconds = Room.phase_seconds
  end

  teardown { Room.phase_seconds = @original_seconds }

  test 'a new Room has the Normal preset and a 90s Captioning deadline' do
    assert @room.normal?
    freeze_time do
      @room.start(by: @host)
      assert_equal 90.seconds.from_now, @room.reload.phase_deadline_at
    end
  end

  test 'Quick and Chill give Captioning 60s and 150s' do
    { quick: 60, chill: 150 }.each do |preset, seconds|
      room = room_with_players
      room.choose_captioning_preset(preset:, by: room.host)
      freeze_time do
        room.start(by: room.host)
        assert_equal seconds.seconds.from_now, room.reload.phase_deadline_at
      end
    end
  end

  test 'the upload grace still extends a Chill Captioning once by 5s' do
    @room.choose_captioning_preset(preset: 'chill', by: @host)
    @room.start(by: @host)
    started = @room.reload.phase_deadline_at
    travel_to(started + 1.second) do
      @room.advance!(from_seq: @room.phase_seq, only_if_due: true)
      assert @room.reload.captioning?
      assert @room.upload_grace_used?
      assert_equal started + 5.seconds, @room.phase_deadline_at
    end
  end

  test 'every Round of the Game uses the preset' do
    @room.choose_captioning_preset(preset: :quick, by: @host)
    @room.start(by: @host)
    freeze_time do
      2.times { @room.advance! }
      assert @room.reload.captioning?
      assert_equal 2, @room.current_round_number
      assert_equal 60.seconds.from_now, @room.phase_deadline_at
    end
  end

  test 'phase_seconds can still override Captioning for tests' do
    Room.phase_seconds = Room.phase_seconds.merge(captioning: 5)
    freeze_time do
      @room.start(by: @host)
      assert_equal 5.seconds.from_now, @room.reload.phase_deadline_at
    end
  end

  test 'only the Host can choose' do
    assert_raises(ActiveRecord::RecordInvalid) do
      @room.choose_captioning_preset(preset: :quick, by: @room.player_for('bob'))
    end
    assert @room.reload.normal?
  end

  test 'an unknown preset is refused with a clear message' do
    error = assert_raises(ActiveRecord::RecordInvalid) { @room.choose_captioning_preset(preset: 'turbo', by: @host) }
    assert_match(/preset/i, error.message)
    assert @room.reload.normal?
  end

  test 'a change during a Game is refused' do
    @room.start(by: @host)
    assert_raises(ActiveRecord::RecordInvalid) { @room.choose_captioning_preset(preset: :quick, by: @host) }
    assert @room.reload.normal?
  end

  test 'a change touches activity' do
    travel_to(1.hour.from_now) do
      @room.choose_captioning_preset(preset: :quick, by: @host)
      assert_in_delta Time.current, @room.reload.last_activity_at, 1
    end
  end

  test 'a Player who becomes Host can change it' do
    bob = @room.player_for('bob')
    @room.update!(host: bob)
    @room.choose_captioning_preset(preset: :chill, by: bob)
    assert @room.reload.chill?
  end

  test 'a change sends every Player the control on their own stream, Host-only buttons only to the Host' do
    ActionCable.server.pubsub.clear
    @room.choose_captioning_preset(preset: :chill, by: @host)

    @room.players.each do |player|
      fragment = capture_turbo_stream_broadcasts([@room, player]).map { |s| Nokogiri::HTML.fragment(s.to_html) }
                                                                 .find { |f| f.at_css('#captioning_preset') }
      assert fragment, "#{player.nickname} got no preset control"
      assert_equal 'chill', fragment.at_css('#captioning_preset')['data-preset']
      assert_equal player == @host, fragment.css('button').any?
    end
    assert_empty capture_turbo_stream_broadcasts(@room)
  end
end
