require 'test_helper'
require 'turbo/broadcastable/test_helper'

class ScoreboardTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    seed_templates(30)
    @host = open_session
    @host.post rooms_path, params: { nickname: 'Ada' }
    @room = Room.live.last
    @bob = open_session
    @bob.post joins_path, params: { code: @room.code, nickname: 'Bob' }
    open_session.post joins_path, params: { code: @room.code, nickname: 'Cy' }
    @host.post start_room_path(@room.code)
  end

  test 'a reload in Captioning renders a countdown from the deadline and server_now' do
    @bob.get room_path(@room.code)

    @bob.assert_select "[data-controller='countdown'][data-countdown-deadline-value]"
    @bob.assert_select '[data-countdown-server-now-value]'
  end

  test 'the Scoreboard lists every Player with place and total, sorted by total, and no countdown' do
    game = @room.reload.current_game
    game.game_players.find_by(nickname: 'Cy').update!(total: 7)
    game.game_players.find_by(nickname: 'Ada').update!(total: 3)
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }

    @bob.get room_path(@room.code)

    @bob.assert_select '#scoreboard li', 3
    @bob.assert_select '#scoreboard li:nth-child(1)', /1.*Cy.*7/m
    @bob.assert_select '#scoreboard li:nth-child(2)', /2.*Ada.*3/m
    @bob.assert_select '#scoreboard li:nth-child(3)', /3.*Bob.*0/m
    @bob.assert_select '[data-controller=countdown]', false
  end

  test 'tied totals share a place' do
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }

    @bob.get room_path(@room.code)

    @bob.assert_select '#scoreboard li', text: /^\s*1\b/, count: 3
  end

  test 'the Host sees preset choices on the Scoreboard and others see it read-only' do
    3.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }

    @host.get room_path(@room.code)
    @host.assert_select "#captioning_preset[data-preset='normal']"
    @host.assert_select '#captioning_preset button', 3
    @bob.get room_path(@room.code)
    @bob.assert_select "#captioning_preset[data-preset='normal']"
    @bob.assert_select '#captioning_preset button', 0
    @bob.assert_select '#captioning_preset', /Normal/
  end

  test 'a preset chosen on the Scoreboard shows in Waiting after Play again' do
    3.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }

    @host.post room_captioning_preset_path(@room.code, preset: 'chill')
    @host.assert_response :redirect
    @bob.get room_path(@room.code)
    @bob.assert_select "#captioning_preset[data-preset='chill']"

    @host.post play_again_room_path(@room.code)
    @bob.get room_path(@room.code)
    @bob.assert_select "#captioning_preset[data-preset='chill']"
    @host.get room_path(@room.code)
    @host.assert_select "#captioning_preset [data-preset-option='chill'][aria-current='true']"
  end

  test 'a non-Host cannot change the preset on the Scoreboard' do
    3.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }

    @bob.post room_captioning_preset_path(@room.code, preset: 'quick')
    @bob.assert_response :unprocessable_content
    assert @room.reload.normal?
  end

  test 'a preset change in Captioning is refused' do
    @host.post room_captioning_preset_path(@room.code, preset: 'quick')
    @host.assert_response :unprocessable_content
    assert @room.reload.normal?
  end

  test 'only the Host sees Play again on the Scoreboard' do
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }

    @host.get room_path(@room.code)
    @host.assert_select 'form[action=?]', play_again_room_path(@room.code)
    @bob.get room_path(@room.code)
    @bob.assert_select 'form[action=?]', play_again_room_path(@room.code), false
  end

  test 'the Host presses Play again and the Room is Waiting with the same Players' do
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }

    @bob.post play_again_room_path(@room.code)
    @bob.assert_response :unprocessable_content
    assert @room.reload.scoreboard?

    @host.post play_again_room_path(@room.code)

    assert @room.reload.waiting?
    @host.get room_path(@room.code)
    @host.assert_select '#players li', 3
    @host.assert_select 'form[action=?]', start_room_path(@room.code)
  end

  test 'Play again is disabled with the reason when fewer than 3 Players are present' do
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }
    Player.find_by!(nickname: 'Cy').update!(away_at: Time.current)

    @host.get room_path(@room.code)

    @host.assert_select 'form[action=?] button[disabled]', play_again_room_path(@room.code)
    @host.assert_select '#play-again-gate-reason', text: /Need 3 present Players, 2 here/
    @host.post play_again_room_path(@room.code)
    @host.assert_response :unprocessable_content
    assert @room.reload.scoreboard?
  end

  test 'a presence change on the Scoreboard re-sends each Players Play again gate' do
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }
    @room.reload
    ActionCable.server.pubsub.clear

    assert_turbo_stream_broadcasts [@room, @room.host], count: 1 do
      @room.broadcast_start_gate!
    end
  end
end
