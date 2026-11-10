require 'test_helper'

class KickPlayerTest < ActionDispatch::IntegrationTest
  setup do
    @host = open_session
    @host.post rooms_path, params: { nickname: 'Ada' }
    @room = Room.live.last
    @bob = open_session.tap { |s| s.post joins_path, params: { code: @room.code, nickname: 'Bob' } }
    @bob_player = @room.players.find_by!(nickname: 'Bob')
  end

  test 'only the Host sees kick actions, and only on other Players' do
    @host.get room_path(@room.code)
    @host.assert_select "form[action='#{kick_room_player_path(@room.code, @bob_player)}']", count: 1
    @host.assert_select "form[action*='/kick']", count: 1

    @bob.get room_path(@room.code)
    @bob.assert_select "form[action*='/kick']", count: 0
  end

  test 'a kick sends the kicked browser back to the join form, and they can rejoin' do
    @host.post kick_room_player_path(@room.code, @bob_player)
    @host.assert_redirected_to room_path(@room.code)

    @bob.get room_path(@room.code)
    @bob.assert_select "form[action='#{joins_path}'] input[name=code][value='#{@room.code}']"
    @bob.post joins_path, params: { code: @room.code, nickname: 'Bob' }
    @bob.assert_redirected_to room_path(@room.code)
  end

  test 'a non-Host cannot kick' do
    @bob.post kick_room_player_path(@room.code, @room.host)
    @bob.assert_response :unprocessable_content
    assert Player.exists?(@room.host_player_id)
  end
end
