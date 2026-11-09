require 'test_helper'

class RecapTest < ActionDispatch::IntegrationTest
  setup do
    seed_templates(30)
    @host = open_session
    @host.post rooms_path, params: { nickname: 'Ada' }
    @room = Room.live.last
    open_session.post joins_path, params: { code: @room.code, nickname: 'Bob' }
    open_session.post joins_path, params: { code: @room.code, nickname: 'Cy' }
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

  test 'the Recap has a title, description and Open Graph meta for link unfurls' do
    finish_game

    get recap_path(@game.recap_token)

    assert_select 'title', /Recap/
    assert_select 'meta[name=description][content]'
    assert_select 'meta[property="og:title"][content]'
    assert_select 'meta[property="og:description"][content]'
  end

  test 'the Recap shows the date the Game finished' do
    finish_game
    @game.update!(finished_at: Time.utc(2026, 3, 14, 12))

    get recap_path(@game.recap_token)

    assert_select '#recap time[datetime]', /March 14, 2026/
  end

  test 'the Recap links to the home page' do
    finish_game

    get recap_path(@game.recap_token)

    assert_select '#recap a[href=?]', root_path
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
end
