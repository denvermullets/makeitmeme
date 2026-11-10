require 'test_helper'

class ScoreboardMemesTabTest < ActionDispatch::IntegrationTest
  setup do
    seed_templates(30)
    @host = open_session
    @host.post rooms_path, params: { nickname: 'Ada' }
    @room = Room.live.last
    @bob = open_session
    @bob.post joins_path, params: { code: @room.code, nickname: 'Bob' }
    open_session.post joins_path, params: { code: @room.code, nickname: 'Cy' }
    @host.post start_room_path(@room.code)
    6.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }
    @game = @room.reload.current_game
    @rounds = @game.rounds.order(:number).to_a
  end

  def make_meme(round, nickname, position:, points:)
    seat = @game.game_players.find_by!(nickname:)
    Meme.create!(round:, game_player: seat, position:, points:).tap do |meme|
      meme.image.attach(io: File.open(file_fixture('drake.png')), filename: 'drake.png', content_type: 'image/png')
    end
  end

  test 'the Scoreboard screen has Scoreboard and Memes tabs that need no request' do
    @bob.get room_path(@room.code)

    @bob.assert_select "#scoreboard [data-controller='tabs'] button[type=button][data-tabs-target='tab']", 2
    @bob.assert_select "#scoreboard button[data-tabs-target='tab']", text: 'Scoreboard'
    @bob.assert_select "#scoreboard button[data-tabs-target='tab']", text: 'Memes'
    @bob.assert_select "#scoreboard [data-tabs-target='panel']", 2
  end

  test 'the Memes tab button is a reveal target, rendered visible so it shows without JavaScript' do
    @bob.get room_path(@room.code)

    @bob.assert_select "#scoreboard[data-controller~='reveal'] button[data-reveal-target='memesTab']", text: 'Memes'
    @bob.assert_select "#scoreboard button[data-reveal-target='memesTab'][hidden]", false
  end

  test 'the Memes tab groups Memes by Round in Round order and by voting position within a Round' do
    make_meme(@rounds[1], 'Cy', position: 0, points: 2)
    make_meme(@rounds[0], 'Bob', position: 1, points: 5)
    make_meme(@rounds[0], 'Ada', position: 0, points: -1)

    @bob.get room_path(@room.code)

    @bob.assert_select '#memes_by_round section[data-round]', 2
    @bob.assert_select '#memes_by_round section[data-round="1"] li', 2
    @bob.assert_select '#memes_by_round section[data-round="1"] li:nth-child(1)[data-nickname="Ada"]'
    @bob.assert_select '#memes_by_round section[data-round="1"] li:nth-child(2)[data-nickname="Bob"]'
    @bob.assert_select '#memes_by_round section[data-round="2"] li[data-nickname="Cy"]'
    sections = @bob.css_select('#memes_by_round section').map { |node| node['data-round'] }
    assert_equal %w[1 2], sections
  end

  test 'each Meme shows its image through the storage proxy, its maker and its points' do
    make_meme(@rounds[0], 'Bob', position: 0, points: 5)

    @bob.get room_path(@room.code)

    @bob.assert_select '#memes_by_round li[data-nickname="Bob"] img[src*="/rails/active_storage/blobs/proxy/"]'
    @bob.assert_select '#memes_by_round li[data-nickname="Bob"]', /Bob/
    @bob.assert_select '#memes_by_round li[data-nickname="Bob"] [data-meme-points]', text: '5'
  end

  test 'a Meme still shows after its Template is hard-deleted' do
    meme = make_meme(@rounds[0], 'Bob', position: 0, points: 1)
    meme.update!(template: Template.first)
    Template.first.destroy!

    @bob.get room_path(@room.code)

    @bob.assert_select '#memes_by_round li[data-nickname="Bob"] img'
  end

  test 'each Meme has a save link to its PNG with a Round and nickname download file name' do
    make_meme(@rounds[1], 'Ada', position: 0, points: 1)

    @bob.get room_path(@room.code)

    @bob.assert_select '#memes_by_round li[data-nickname="Ada"] a[data-meme-save][download="round-2-ada.png"][href*="/rails/active_storage/blobs/proxy/"][data-controller="meme-save"][data-action="click->meme-save#save"]',
                       text: /Save/
  end

  test 'the download file name uses a filename-safe nickname' do
    @game.game_players.find_by!(nickname: 'Cy').update!(nickname: 'Cy / The "Ace"!')
    make_meme(@rounds[0], 'Cy / The "Ace"!', position: 0, points: 1)

    @bob.get room_path(@room.code)

    @bob.assert_select '#memes_by_round a[data-meme-save][download="round-1-cy-the-ace.png"]'
  end

  test 'a nickname with no filename-safe characters falls back to player' do
    @game.game_players.find_by!(nickname: 'Cy').update!(nickname: '🔥🔥')
    make_meme(@rounds[0], '🔥🔥', position: 0, points: 1)

    @bob.get room_path(@room.code)

    @bob.assert_select '#memes_by_round a[data-meme-save][download="round-1-player.png"]'
  end

  test 'a Meme with no image has no save link' do
    @game.game_players.find_by!(nickname: 'Ada').then do |seat|
      Meme.create!(round: @rounds[0], game_player: seat, position: 0, points: 0)
    end

    @bob.get room_path(@room.code)

    @bob.assert_select '#memes_by_round a[data-meme-save]', false
  end

  test 'the top-points Meme of each Round carries the Meme of the Round badge and others do not' do
    make_meme(@rounds[0], 'Ada', position: 0, points: 2)
    make_meme(@rounds[0], 'Bob', position: 1, points: 5)
    make_meme(@rounds[1], 'Cy', position: 0, points: -1)

    @bob.get room_path(@room.code)

    @bob.assert_select '#memes_by_round [data-meme-badge]', 2
    @bob.assert_select '#memes_by_round li[data-nickname="Bob"] [data-meme-badge]'
    @bob.assert_select '#memes_by_round li[data-nickname="Ada"] [data-meme-badge]', 0
    @bob.assert_select '#memes_by_round section[data-round="2"] li[data-nickname="Cy"] [data-meme-badge]'
  end

  test 'tied top Memes in a Round all carry the badge' do
    make_meme(@rounds[0], 'Ada', position: 0, points: 4)
    make_meme(@rounds[0], 'Bob', position: 1, points: 4)
    make_meme(@rounds[0], 'Cy', position: 2, points: 1)

    @bob.get room_path(@room.code)

    @bob.assert_select '#memes_by_round li[data-nickname="Ada"] [data-meme-badge]'
    @bob.assert_select '#memes_by_round li[data-nickname="Bob"] [data-meme-badge]'
    @bob.assert_select '#memes_by_round li[data-nickname="Cy"] [data-meme-badge]', 0
  end

  test 'the Memes list badge agrees with the Scoreboard badge' do
    make_meme(@rounds[0], 'Ada', position: 0, points: 4)
    make_meme(@rounds[0], 'Bob', position: 1, points: 4)
    make_meme(@rounds[1], 'Cy', position: 0, points: 3)

    @bob.get room_path(@room.code)

    %w[Ada Bob Cy].each do |nick|
      @bob.assert_select "#memes_by_round li[data-nickname='#{nick}'] [data-meme-badge]", 1
      @bob.assert_select "#scoreboard ol li[data-nickname='#{nick}'] [data-meme-of-the-round]", 1
    end
  end
end
