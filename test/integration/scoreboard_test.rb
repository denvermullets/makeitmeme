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

  test 'the Scoreboard shows Buddies received, summed from the cached Buddy counts over the Game' do
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }
    game = @room.reload.current_game
    ada = game.game_players.find_by!(nickname: 'Ada')
    bob = game.game_players.find_by!(nickname: 'Bob')
    rounds = game.rounds.order(:number).to_a
    Meme.create!(round: rounds[0], game_player: ada, buddy_count: 2)
    Meme.create!(round: rounds[1], game_player: ada, buddy_count: 1)
    Meme.create!(round: rounds[0], game_player: bob, buddy_count: 4)

    @bob.get room_path(@room.code)

    @bob.assert_select "#scoreboard li[data-nickname='Ada'] [data-buddies-received]", text: '3'
    @bob.assert_select "#scoreboard li[data-nickname='Bob'] [data-buddies-received]", text: '4'
    @bob.assert_select "#scoreboard li[data-nickname='Cy'] [data-buddies-received]", text: '0'
  end

  def finish_game_with(memes)
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }
    game = @room.reload.current_game
    rounds = game.rounds.order(:number).to_a
    memes.each do |round_index, nickname, points|
      Meme.create!(round: rounds[round_index], game_player: game.game_players.find_by!(nickname:), points:)
    end
    @bob.get room_path(@room.code)
  end

  def badge(nickname) = "#scoreboard li[data-nickname='#{nickname}'] [data-meme-of-the-round]"

  test 'a Player with one Meme of the Round shows the badge without a count' do
    finish_game_with([[0, 'Ada', 5], [0, 'Bob', 2]])

    @bob.assert_select badge('Ada'), 1
    @bob.assert_select "#{badge('Ada')} [data-count]", false
    @bob.assert_select badge('Bob'), false
    @bob.assert_select badge('Cy'), false
  end

  test 'a Player with several Memes of the Round shows the badge with the count' do
    finish_game_with([[0, 'Ada', 5], [1, 'Ada', 4], [2, 'Ada', 3], [0, 'Bob', 1], [1, 'Bob', 1], [2, 'Bob', 1]])

    @bob.assert_select "#{badge('Ada')} [data-count]", text: '3'
    @bob.assert_select badge('Bob'), false
  end

  test 'tied top Memes in a Round credit every maker' do
    finish_game_with([[0, 'Ada', 5], [0, 'Bob', 5], [0, 'Cy', 1]])

    @bob.assert_select badge('Ada'), 1
    @bob.assert_select badge('Bob'), 1
    @bob.assert_select badge('Cy'), false
  end

  test 'a Round with no Memes credits nobody' do
    finish_game_with([])

    @bob.assert_select '#scoreboard [data-meme-of-the-round]', false
  end

  test 'the count is of Rounds won, including shared wins' do
    finish_game_with([[0, 'Ada', 5], [1, 'Ada', 5], [1, 'Bob', 5]])

    @bob.assert_select "#{badge('Ada')} [data-count]", text: '2'
    @bob.assert_select "#{badge('Bob')} [data-count]", false
  end

  test 'the Scoreboard shows points per Round in Round order, none for a missing Meme, signed, summing to the total' do
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }
    game = @room.reload.current_game
    ada = game.game_players.find_by!(nickname: 'Ada')
    bob = game.game_players.find_by!(nickname: 'Bob')
    rounds = game.rounds.order(:number).to_a
    Meme.create!(round: rounds[0], game_player: ada, points: 3)
    Meme.create!(round: rounds[2], game_player: ada, points: -1)
    Meme.create!(round: rounds[1], game_player: bob, points: 0)
    ada.update!(total: 2)

    @bob.get room_path(@room.code)

    @bob.assert_select "#scoreboard li[data-nickname='Ada'] [data-round-points]", 3
    @bob.assert_select "#scoreboard li[data-nickname='Ada'] [data-round-points='1']", text: '3'
    @bob.assert_select "#scoreboard li[data-nickname='Ada'] [data-round-points='2']", text: 'none'
    @bob.assert_select "#scoreboard li[data-nickname='Ada'] [data-round-points='3']", text: '-1'
    @bob.assert_select "#scoreboard li[data-nickname='Bob'] [data-round-points='1']", text: 'none'
    @bob.assert_select "#scoreboard li[data-nickname='Bob'] [data-round-points='2']", text: '0'
    @bob.assert_select "#scoreboard li[data-nickname='Cy'] [data-round-points]", text: 'none', count: 3
  end

  test 'tied totals share a place' do
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }

    @bob.get room_path(@room.code)

    @bob.assert_select '#scoreboard li', text: /^\s*1\b/, count: 3
  end

  test 'the Scoreboard carries the reveal anchor and each places as data attributes and renders every row' do
    game = @room.reload.current_game
    game.game_players.find_by(nickname: 'Cy').update!(total: 7)
    game.game_players.find_by(nickname: 'Ada').update!(total: 3)
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }
    finished_at = @room.reload.current_game.finished_at

    @bob.get room_path(@room.code)

    @bob.assert_select "#scoreboard[data-controller='reveal'][data-reveal-finished-at-value=?]", finished_at.iso8601(3)
    @bob.assert_select '#scoreboard[data-reveal-server-now-value]'
    @bob.assert_select '#scoreboard li', 3
    @bob.assert_select "#scoreboard li[data-reveal-target='row'][data-place='1'][data-nickname='Cy']"
    @bob.assert_select "#scoreboard li[data-reveal-target='row'][data-place='2'][data-nickname='Ada']"
    @bob.assert_select "#scoreboard li[data-reveal-target='row'][data-place='3'][data-nickname='Bob']"
    @bob.assert_select '#scoreboard li[hidden]', false
  end

  test 'the Host sees preset choices on the Scoreboard and others see it read-only' do
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }

    @host.get room_path(@room.code)
    @host.assert_select "#captioning_preset[data-preset='normal']"
    @host.assert_select '#captioning_preset button', 3
    @bob.get room_path(@room.code)
    @bob.assert_select "#captioning_preset[data-preset='normal']"
    @bob.assert_select '#captioning_preset button', 0
    @bob.assert_select '#captioning_preset', /Normal/
  end

  test 'a preset chosen on the Scoreboard shows in Waiting after Play again' do
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }

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
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }

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
