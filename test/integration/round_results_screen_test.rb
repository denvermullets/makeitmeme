require 'test_helper'

# The Round's results: once every Meme of the Round has been voted on, every phone sees each Meme's maker, points
# and counts at once. Nothing is scored on screen before that.
class RoundResultsScreenTest < ActionDispatch::IntegrationTest
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
    voters = @sessions.keys - [@maker]
    @sessions[voters.first].post room_votes_path(@room.code), params: { meme_id: @meme.id, kind: 'up' }
    @sessions[voters.last].post room_votes_path(@room.code), params: { meme_id: @meme.id, kind: 'down' }
    3.times { travel_to(@room.reload.phase_deadline_at + 2.seconds) { @room.advance! } if @room.reload.vote? }
  end

  def entry(meme = @meme) = "#round_results li[data-meme-id='#{meme.id}']"

  test 'after the last vote of the Round the results stay up for 60s' do
    assert @room.reload.standings?
    assert_in_delta 60, @room.phase_deadline_at - @room.updated_at, 0.5
  end

  test 'every phone, the maker included, sees every Meme with maker, points and counts; a reload is the same' do
    2.times do
      @sessions.each_value do |session|
        session.get room_path(@room.code)
        session.assert_select '#round_results li', 3
        session.assert_select "#{entry} img"
        session.assert_select entry, text: /Made by\s*#{@maker}/
        session.assert_select "#{entry} [data-meme-points]", text: '0'
        session.assert_select "#{entry} [data-meme-counts]", text: /1\s*up.*0\s*meh.*1\s*down/mi
        session.assert_select "#standings [data-controller='countdown']"
      end
    end
  end

  test 'the Buddy count shows beside the counts, with no giver named' do
    @meme.update!(buddy_count: 2)
    @sessions['Ada'].get room_path(@room.code)
    @sessions['Ada'].assert_select "#{entry} [data-meme-counts]", text: /2\s*Buddies/i
  end

  test 'a Redux count shows only when the Meme got one' do
    @sessions['Ada'].get room_path(@room.code)
    @sessions['Ada'].assert_select "#{entry} [data-redux-count]", 0
    @meme.update!(redux_count: 1)
    @sessions['Ada'].get room_path(@room.code)
    @sessions['Ada'].assert_select "#{entry} [data-redux-count]", text: /1 Redux/
  end

  test 'negative points show with a minus sign, positive ones with a plus' do
    @meme.update!(points: -2)
    Meme.where.not(id: @meme.id).first.update!(points: 4)
    @sessions['Ada'].get room_path(@room.code)
    @sessions['Ada'].assert_select "#{entry} [data-meme-points]", text: '-2'
    @sessions['Ada'].assert_select '#round_results [data-meme-points]', text: '+4'
  end

  test 'the Standings list each missed vote beside the total' do
    @sessions['Ada'].get room_path(@room.code)
    @sessions['Ada'].assert_select "#standings ol li[data-nickname='#{@maker}'] [data-missed-votes='2']",
                                   text: /2 missed votes \(-2\)/
  end
end
