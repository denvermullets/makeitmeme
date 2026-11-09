require 'test_helper'

# A returning browser (same token cookie) resumes its Player with the full current state on a plain page load.
class ResumePlayerTest < ActionDispatch::IntegrationTest
  setup do
    seed_templates(30)
    @sessions = { 'Ada' => open_session }
    @sessions['Ada'].post rooms_path, params: { nickname: 'Ada' }
    @room = Room.live.last
    %w[Bob Cy].each do |name|
      @sessions[name] = open_session.tap { |s| s.post joins_path, params: { code: @room.code, nickname: name } }
    end
  end

  def resume(name)
    session = @sessions[name]
    session.get room_path(@room.code)
    session.assert_response :success
    session.assert_select 'turbo-cable-stream-source', count: 2
    session
  end

  def start_game
    @sessions['Ada'].post start_room_path(@room.code)
    @room.reload
  end

  def tokens_by_nickname = @room.players.to_h { |player| [player.nickname, player.browser_token] }

  test 'Waiting: reopening the Room link skips the join form and lists the Players' do
    resume('Bob').assert_select '#waiting #players li', count: 3
  end

  test 'Captioning: the resumed page shows the same Hand that was dealt' do
    start_game
    dealt = @room.hand_for(@room.players.find_by(nickname: 'Bob')).template_ids
    editor = resume('Bob').css_select('#hand [data-controller~="meme-editor"]').first
    assert_equal dealt, JSON.parse(editor['data-meme-editor-hand-value']).pluck('id')
    assert_not_nil editor['data-meme-editor-deadline-value']
  end

  test 'Captioning: after submitting, the resumed page says how many others are still to submit' do
    start_game
    submit_memes(@room, tokens_by_nickname['Bob'])
    session = resume('Bob')
    session.assert_select '#hand .meme-submitted'
    session.assert_select '#hand', text: /Waiting for 2 others…/
  end

  test 'Captioning: waiting for one other reads in the singular' do
    start_game
    submit_memes(@room, tokens_by_nickname['Bob'], tokens_by_nickname['Cy'])
    resume('Bob').assert_select '#hand', text: /Waiting for 1 other…/
  end

  test "Vote: the resumed page shows the Meme, the countdown and the Player's own Vote" do
    start_game
    submit_memes(@room, *tokens_by_nickname.values)
    travel_to(@room.phase_deadline_at + 2.seconds) { @room.advance! }
    meme = @room.reload.current_meme
    voter = (@sessions.keys - [meme.game_player.nickname]).first
    @sessions[voter].post room_votes_path(@room.code), params: { meme_id: meme.id, kind: 'down' }

    session = resume(voter)
    session.assert_select '#vote img'
    session.assert_select "#vote [data-controller='countdown']"
    session.assert_select "#vote_controls button[value='down'][aria-pressed='true']"
  end

  test 'Reveal: the resumed page shows the Meme and its score' do
    start_game
    submit_memes(@room, *tokens_by_nickname.values)
    travel_to(@room.phase_deadline_at + 2.seconds) { @room.advance! }
    travel_to(@room.reload.phase_deadline_at + 2.seconds) { @room.advance! }
    assert @room.reload.reveal?
    resume('Cy').assert_select '#reveal #reveal_points'
  end

  test 'Scoreboard: the resumed page shows the final totals' do
    start_game
    @room.update!(phase: :scoreboard)
    resume('Cy').assert_select '#scoreboard li', count: 3
  end
end
