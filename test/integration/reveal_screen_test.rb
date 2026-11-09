require 'test_helper'

class RevealScreenTest < ActionDispatch::IntegrationTest
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
    @voters = (@sessions.keys - [@maker])
    @sessions[@voters.first].post room_votes_path(@room.code), params: { meme_id: @meme.id, kind: 'up' }
    @sessions[@voters.last].post room_votes_path(@room.code), params: { meme_id: @meme.id, kind: 'down' }
    travel_to(@room.reload.phase_deadline_at + 2.seconds) { @room.advance! }
  end

  test 'every phone, including the maker, sees the maker, points, counts and a countdown; a reload is the same' do
    2.times do
      @sessions.each_value do |session|
        session.get room_path(@room.code)
        session.assert_select '#reveal img'
        session.assert_select '#reveal', text: /#{@maker}/
        session.assert_select '#reveal_points', text: /0/
        session.assert_select '#reveal_counts', text: /1\s*up.*0\s*meh.*1\s*down/mi
        session.assert_select "#reveal [data-controller='countdown']"
      end
    end
  end

  test 'negative points show with a minus sign' do
    @meme.update!(points: -2)
    @sessions['Ada'].get room_path(@room.code)
    @sessions['Ada'].assert_select '#reveal_points', text: /-2/
  end
end
