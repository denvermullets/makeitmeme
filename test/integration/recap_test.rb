require 'test_helper'

class RecapTest < ActionDispatch::IntegrationTest
  setup do
    seed_templates(30)
    @host = open_session
    @host.post rooms_path, params: { nickname: 'Ada' }
    @room = Room.live.last
    @bob = open_session.tap { |s| s.post joins_path, params: { code: @room.code, nickname: 'Bob' } }
    @cy = open_session.tap { |s| s.post joins_path, params: { code: @room.code, nickname: 'Cy' } }
    @host.post start_room_path(@room.code)
    @game = @room.reload.current_game
  end

  def finish_game
    @game.game_players.find_by(nickname: 'Cy').update!(total: 7)
    @game.game_players.find_by(nickname: 'Ada').update!(total: 3)
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }
    @game.reload
  end

  test 'a fresh session with no cookie can open a finished Game Recap by its token' do
    finish_game

    get recap_path(@game.recap_token)

    assert_response :success
    assert_select 'li', 3
    assert_select 'li:nth-child(1)', /1.*Cy.*7/m
    assert_select 'li:nth-child(2)', /2.*Ada.*3/m
  end

  test 'the Recap has no Host controls, reveal, or Room stream subscription' do
    finish_game

    get recap_path(@game.recap_token)

    assert_select 'form', false
    assert_select 'turbo-cable-stream-source', false
    assert_select '[data-controller]', false
  end

  test 'an unknown or malformed token is a 404' do
    finish_game

    get recap_path('nope')
    assert_response :not_found

    get recap_path('x' * 24)
    assert_response :not_found
  end

  test 'an in-progress Game token is a 404' do
    get recap_path(@game.recap_token)

    assert_response :not_found
  end

  def recap_html
    get recap_path(@game.recap_token)
    assert_response :success
    response.body
  end

  test 'the Recap is unchanged after Play again and a new Game in the same Room' do
    finish_game
    before = recap_html

    @host.post play_again_room_path(@room.code)
    @host.post start_room_path(@room.code)
    assert_not_equal @game.id, @room.reload.current_game.id

    assert_equal before, recap_html
  end

  test 'the Recap is unchanged after a Player Leaves or is kicked' do
    finish_game
    before = recap_html

    @host.post play_again_room_path(@room.code)
    @bob.post leave_room_path(@room.code)
    @host.post kick_room_player_path(@room.code, @room.players.find_by!(nickname: 'Cy'))

    assert_nil @game.game_players.find_by!(nickname: 'Bob').player_id
    assert_nil @game.game_players.find_by!(nickname: 'Cy').player_id
    assert_equal before, recap_html
  end

  test 'the Recap is unchanged after the Room expires' do
    finish_game
    before = recap_html

    @room.update_columns(last_activity_at: 2.days.ago)
    assert @room.reload.expire_if_idle!

    assert_equal 0, Player.where(room_id: @room.id).count
    assert_equal before, recap_html
  end

  test 'nicknames come from the game-player snapshot' do
    finish_game
    @game.game_players.find_by(nickname: 'Cy').update_columns(nickname: 'Snapshot')
    @room.players.find_by!(nickname: 'Ada').update_columns(nickname: 'Renamed')

    body = recap_html

    assert_includes body, 'Snapshot'
    assert_not_includes body, 'Renamed'
  end
end
