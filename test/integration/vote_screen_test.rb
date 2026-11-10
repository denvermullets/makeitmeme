require 'test_helper'

class VoteScreenTest < ActionDispatch::IntegrationTest
  setup do
    seed_templates(30)
    @sessions = { 'Ada' => open_session }
    @sessions['Ada'].post rooms_path, params: { nickname: 'Ada' }
    @room = Room.live.last
    %w[Bob Cy].each do |name|
      @sessions[name] = open_session.tap { |s| s.post joins_path, params: { code: @room.code, nickname: name } }
    end
    @sessions['Ada'].post start_room_path(@room.code)
    @room.reload
    submit_memes(@room, *@room.players.pluck(:browser_token))
    @meme = @room.reload.current_meme
    @maker = @meme.game_player.nickname
    @voter = (@sessions.keys - [@maker]).first
  end

  test 'every phone shows the Meme image and a countdown, and the vote screen never names the maker' do
    @sessions.each_value do |session|
      session.get room_path(@room.code)
      session.assert_select '#vote img'
      session.assert_select "#vote [data-controller='countdown']"
    end
    @sessions[@voter].get room_path(@room.code)
    @sessions[@voter].assert_select '#vote', text: /#{@maker}/, count: 0
  end

  test 'a voter sees up, meh and down buttons' do
    @sessions[@voter].get room_path(@room.code)
    %w[up meh down].each do |kind|
      @sessions[@voter].assert_select "#vote_controls form button[value='#{kind}']"
    end
  end

  test 'a voter sees a Buddy button, spends it with one tap, and every button is then disabled' do
    @sessions[@voter].get room_path(@room.code)
    @sessions[@voter].assert_select "#vote_controls form button[value='buddy']"
    @sessions[@voter].post room_votes_path(@room.code), params: { meme_id: @meme.id, kind: 'buddy' }
    @sessions[@voter].assert_response :no_content

    @sessions[@voter].get room_path(@room.code)
    @sessions[@voter].assert_select '#vote_controls button[disabled]', 4
    @sessions[@voter].assert_select "#vote_controls button[value='buddy'][aria-pressed='true']"
  end

  test 'the Buddy button shows how many are left and is disabled at 0' do
    @sessions[@voter].get room_path(@room.code)
    @sessions[@voter].assert_select "#vote_controls button[value='buddy']", text: /Buddy ×2/

    @room.reload.current_game.game_players.find_by(nickname: @voter).update!(buddies_left: 0)
    @sessions[@voter].get room_path(@room.code)
    @sessions[@voter].assert_select "#vote_controls button[value='buddy']", text: /Buddy ×0/
    @sessions[@voter].assert_select "#vote_controls button[value='buddy'][disabled]"
    @sessions[@voter].assert_select "#vote_controls button[value='up']:not([disabled])"
  end

  test 'a Buddy tap with none left is refused and writes nothing' do
    @room.current_game.game_players.find_by(nickname: @voter).update!(buddies_left: 0)
    @sessions[@voter].post room_votes_path(@room.code), params: { meme_id: @meme.id, kind: 'buddy' }

    assert_not_equal 204, @sessions[@voter].response.status
    assert_equal 0, @meme.votes.count
  end

  test 'the maker sees this one is theirs and no buttons' do
    @sessions[@maker].get room_path(@room.code)
    @sessions[@maker].assert_select '#vote_controls', text: /this one's yours/i
    @sessions[@maker].assert_select '#vote_controls button', 0
  end

  test 'tapping locks the Vote, and a reload shows the locked choice with the buttons disabled' do
    @sessions[@voter].post room_votes_path(@room.code), params: { meme_id: @meme.id, kind: 'meh' }
    @sessions[@voter].assert_response :no_content

    @sessions[@voter].get room_path(@room.code)
    @sessions[@voter].assert_select '#vote_controls button[disabled]', 4
    @sessions[@voter].assert_select "#vote_controls button[value='meh'][aria-pressed='true']"
    @sessions[@voter].assert_select '#vote img'
    @sessions[@voter].assert_select "[data-controller='countdown']"
  end

  test 'a rejected Vote answers 422 and stores nothing' do
    @sessions[@maker].post room_votes_path(@room.code), params: { meme_id: @meme.id, kind: 'up' }
    @sessions[@maker].assert_response :unprocessable_content
    assert_equal 0, Vote.count
  end

  test 'a browser with no seat is turned away' do
    stranger = open_session
    stranger.post room_votes_path(@room.code), params: { meme_id: @meme.id, kind: 'up' }
    stranger.assert_response :unauthorized
  end

  test 'no score or maker is shown while voting, even after a Vote, and closing the vote reveals nothing' do
    @sessions[@voter].post room_votes_path(@room.code), params: { meme_id: @meme.id, kind: 'up' }
    @sessions[@voter].get room_path(@room.code)
    @sessions[@voter].assert_select '[data-meme-points]', 0
    @sessions[@voter].assert_select '#vote', text: /Made by/, count: 0

    travel_to(@room.phase_deadline_at + 1.second) { @room.advance! }
    assert @room.reload.vote? || @room.standings?
    @sessions[@voter].get room_path(@room.code)
    @sessions[@voter].assert_select '#reveal', 0
  end
end
