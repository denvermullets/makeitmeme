require 'test_helper'
require 'turbo/broadcastable/test_helper'

class RoomHostHandoffTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    travel_to Time.zone.parse('2026-11-09 12:00')
    @room = Room.create_with_host(nickname: 'Ada', browser_token: 'ada')
    travel 1.minute
    Room.join(code: @room.code, nickname: 'Cy', browser_token: 'cy')
    travel 1.minute
    Room.join(code: @room.code, nickname: 'Bob', browser_token: 'bob')
    @room.reload
    clear_enqueued_jobs
    ActionCable.server.pubsub.clear
  end

  teardown { travel_back }

  def go_away(token)
    player = @room.player_for(token)
    player.connected!
    player.disconnected!
    travel Player::AWAY_GRACE + 1.second
    perform_enqueued_jobs(only: PresenceGraceJob)
  end

  def host_token = @room.reload.host.browser_token

  test 'the Host going Away hands the role to the earliest-joined present Player' do
    go_away('ada')
    assert_equal 'cy', host_token
  end

  test 'handoff skips Away Players and goes in joined_at order' do
    go_away('cy')
    go_away('ada')
    assert_equal 'bob', host_token
  end

  test 'the original Host returning does not take the role back' do
    go_away('ada')
    @room.player_for('ada').connected!
    assert_equal 'cy', host_token
    assert @room.reload.player_for('ada').here?
  end

  test 'an Away non-Host leaves the Host alone' do
    go_away('bob')
    assert_equal 'ada', host_token
  end

  test 'an Away Host with nobody to hand off to is still the Host' do
    go_away('cy')
    go_away('bob')
    go_away('ada')
    ada = @room.reload.player_for('ada')
    assert ada.away?
    assert @room.host?(ada)
  end

  test 'with nobody else present the Host stays' do
    go_away('cy')
    go_away('bob')
    go_away('ada')
    assert_equal 'ada', host_token
  end

  test 'handoff happens during a Game' do
    seed_templates(30)
    @room.start(by: @room.player_for('ada'))
    go_away('ada')
    assert_equal 'cy', host_token
    assert @room.reload.captioning?
  end

  test 'handoff on the Scoreboard gives the new Host Play again' do
    @room.update!(phase: :scoreboard, current_game: Game.create!(room: @room, status: :finished))
    go_away('ada')
    assert_equal 'cy', host_token
  end

  test 'the new Host gets Host controls and kick buttons on their own stream' do
    cy = @room.player_for('cy')
    streams = capture_turbo_stream_broadcasts([@room, cy])
    assert_empty streams

    go_away('ada')
    html = capture_turbo_stream_broadcasts([@room, cy]).map(&:to_html).join
    assert_includes html, 'Kick'
    assert_includes html, 'start_gate'
    assert_includes html, '(Host)'
  end

  test 'hand_off_host! for Leave falls back to Away Players, then to no Host' do
    go_away('cy')
    go_away('bob')
    ada = @room.player_for('ada')
    assert_equal 'cy', @room.hand_off_host!(from: ada, fallback_to_away: true).browser_token
    @room.remove_player!(ada)
    @room.remove_player!(@room.player_for('bob'))
    @room.reload.hand_off_host!(from: @room.player_for('cy'), fallback_to_away: true)
    assert_nil @room.reload.host
  end

  test 'hand_off_host! does nothing when the given Player is not the Host' do
    assert_nil @room.hand_off_host!(from: @room.player_for('bob'))
    assert_equal 'ada', host_token
  end
end
