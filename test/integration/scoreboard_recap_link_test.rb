require 'test_helper'

class ScoreboardRecapLinkTest < ActionDispatch::IntegrationTest
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
    @path = "/recap/#{@game.recap_token}"
  end

  test 'a reloaded Scoreboard screen shows the Recap link with a copy or share control' do
    @bob.get room_path(@room.code)

    @bob.assert_select "#scoreboard [data-controller='share'][data-share-url-value='#{@path}']"
    @bob.assert_select "#scoreboard a[data-recap-url][href='#{@path}']", text: @path
    @bob.assert_select "#scoreboard [data-controller='share'] button[data-action='share#share']"
  end

  test 'the Scoreboard screen broadcast to each Player carries the same Recap path' do
    player = @room.player_for('bob')
    html = ApplicationController.render(partial: 'rooms/screen', locals: { room: @room, player: })

    assert_includes html, @path
  end
end
