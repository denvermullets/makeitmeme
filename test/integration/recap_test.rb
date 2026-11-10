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
    @game.game_players.find_by(nickname: 'Cy').update!(total: 7, buddies_left: 0)
    @game.game_players.find_by(nickname: 'Ada').update!(total: 3, buddies_left: 0)
    @game.game_players.find_by(nickname: 'Bob').update!(buddies_left: 0)
    6.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }
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
    assert_select 'title', /404/

    get recap_path('x' * 24)
    assert_response :not_found
  end

  test 'an in-progress Game token is a 404' do
    get recap_path(@game.recap_token)

    assert_response :not_found
  end

  def make_meme(round, nickname, position:, points:)
    seat = @game.game_players.find_by!(nickname:)
    Meme.create!(round:, game_player: seat, position:, points:).tap do |meme|
      meme.image.attach(io: File.open(file_fixture('drake.png')), filename: 'drake.png', content_type: 'image/png')
    end
  end

  test 'the Recap shows every Meme grouped by Round in voting order with maker and points' do
    finish_game
    rounds = @game.rounds.order(:number).to_a
    make_meme(rounds[1], 'Cy', position: 0, points: 2)
    make_meme(rounds[0], 'Bob', position: 1, points: 5)
    make_meme(rounds[0], 'Ada', position: 0, points: -1)

    get recap_path(@game.recap_token)

    assert_response :success
    assert_select '#recap #memes_by_round section[data-round]', 2
    assert_select '#memes_by_round section[data-round="1"] li:nth-child(1)[data-nickname="Ada"] [data-meme-points]',
                  '-1'
    assert_select '#memes_by_round section[data-round="1"] li:nth-child(2)[data-nickname="Bob"] [data-meme-points]', '5'
    assert_select '#memes_by_round section[data-round="2"] li[data-nickname="Cy"] img[src*="/rails/active_storage/"]'
  end

  test 'the Recap Memes still render after the Room expires and after a Template is deleted' do
    finish_game
    make_meme(@game.rounds.order(:number).first, 'Bob', position: 0, points: 4)
    @room.update!(expired_at: Time.current)
    Template.destroy_all

    get recap_path(@game.recap_token)

    assert_response :success
    assert_select '#memes_by_round li[data-nickname="Bob"]'
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
