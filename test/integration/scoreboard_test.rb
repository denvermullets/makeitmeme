require 'test_helper'

class ScoreboardTest < ActionDispatch::IntegrationTest
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
    3.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }

    @bob.get room_path(@room.code)

    @bob.assert_select '#scoreboard li', 3
    @bob.assert_select '#scoreboard li:nth-child(1)', /1.*Cy.*7/m
    @bob.assert_select '#scoreboard li:nth-child(2)', /2.*Ada.*3/m
    @bob.assert_select '#scoreboard li:nth-child(3)', /3.*Bob.*0/m
    @bob.assert_select '[data-controller=countdown]', false
  end

  test 'tied totals share a place' do
    3.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }

    @bob.get room_path(@room.code)

    @bob.assert_select '#scoreboard li', text: /^\s*1\b/, count: 3
  end
end
