require 'test_helper'

class StandingsScreenTest < ActionDispatch::IntegrationTest
  setup do
    seed_templates(30)
    @sessions = { 'Ada' => open_session }
    @sessions['Ada'].post rooms_path, params: { nickname: 'Ada' }
    @room = Room.live.last
    %w[Bob Cy].each do |name|
      @sessions[name] = open_session.tap { |s| s.post joins_path, params: { code: @room.code, nickname: name } }
    end
    @sessions['Ada'].post start_room_path(@room.code)
    @room.reload.advance! # an empty Round 1 goes through Standings
  end

  test 'every phone, a reload included, sees the Standings heading and a countdown' do
    assert @room.reload.standings?
    2.times do
      @sessions.each_value do |session|
        session.get room_path(@room.code)
        session.assert_select '#standings', text: /Standings/
        session.assert_select "#standings [data-controller='countdown']"
      end
    end
  end

  test 'lists every game-player with place and total, highest first, ties sharing a place, negatives with a minus' do
    game = @room.reload.current_game
    game.game_players.find_by(nickname: 'Cy').update!(total: 7)
    game.game_players.find_by(nickname: 'Ada').update!(total: -2)
    game.game_players.find_by(nickname: 'Bob').update!(total: -2)

    @sessions['Bob'].get room_path(@room.code)

    @sessions['Bob'].assert_select '#standings li', 3
    @sessions['Bob'].assert_select '#standings li:nth-child(1)', /1.*Cy.*7/m
    @sessions['Bob'].assert_select '#standings li:nth-child(2)', /2.*Ada.*-2/m
    @sessions['Bob'].assert_select '#standings li:nth-child(3)', /2.*Bob.*-2/m
  end

  test 'an Away Player is still listed with the Away marker' do
    Player.find_by!(nickname: 'Cy').update!(away_at: Time.current)

    @sessions['Ada'].get room_path(@room.code)

    @sessions['Ada'].assert_select '#standings li', 3
    @sessions['Ada'].assert_select '#standings li', text: /Cy.*Away/mi
    @sessions['Ada'].assert_select '#standings li', text: /Away/i, count: 1
  end

  test 'a Spectator sees the Standings screen, not the spectator screen' do
    spectator = open_session
    spectator.post joins_path, params: { code: @room.code, nickname: 'Dee' }

    spectator.get room_path(@room.code)

    spectator.assert_select '#standings li', 3
  end

  test 'every phone sees the Meme of the Round with its maker, ties sharing it' do
    round = @room.current_game.rounds.find_by!(number: 1)
    submit_memes_for_round(round, 'Ada' => 3, 'Bob' => 3, 'Cy' => 1)

    @sessions.each_value do |session|
      session.get room_path(@room.code)
      session.assert_select '#standings #meme_of_the_round img', 2
      session.assert_select '#standings #meme_of_the_round', text: /Ada/
      session.assert_select '#standings #meme_of_the_round', text: /Bob/
      session.assert_select '#standings #meme_of_the_round', text: /Cy/, count: 0
    end
  end

  test 'a Round with no Memes shows no Meme of the Round' do
    @sessions['Ada'].get room_path(@room.code)

    @sessions['Ada'].assert_select '#meme_of_the_round', 0
  end

  private

  def submit_memes_for_round(round, points_by_nickname)
    points_by_nickname.each do |nickname, points|
      blob = ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture('drake.png')),
                                                    filename: 'drake.png', content_type: 'image/png')
      gp = @room.current_game.game_players.find_by!(nickname:)
      meme = round.memes.new(game_player: gp, points:)
      meme.image.attach(blob)
      meme.save!
    end
  end
end
