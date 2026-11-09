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
    5.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }
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
end
