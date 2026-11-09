require 'test_helper'

class LeaveRoomTest < ActionDispatch::IntegrationTest
  setup do
    @host = open_session
    @host.post rooms_path, params: { nickname: 'Ada' }
    @room = Room.live.last
    @bob = open_session.tap { |s| s.post joins_path, params: { code: @room.code, nickname: 'Bob' } }
  end

  test 'every Player sees Leave Room in Waiting' do
    [@host, @bob].each do |session|
      session.get room_path(@room.code)
      session.assert_select "form[action='#{leave_room_path(@room.code)}']", count: 1
    end
  end

  test 'leaving sends the browser to the join page and frees the nickname' do
    @bob.post leave_room_path(@room.code)
    @bob.assert_redirected_to root_path
    assert_equal ['Ada'], @room.players.pluck(:nickname)
    @bob.get room_path(@room.code)
    @bob.assert_redirected_to root_path
  end

  test 'the server rejects Leave mid-Game and no Leave is shown' do
    seed_templates(30)
    open_session.post joins_path, params: { code: @room.code, nickname: 'Cy' }
    @host.post start_room_path(@room.code)
    assert @room.reload.captioning?
    @host.get room_path(@room.code)
    @host.assert_select "form[action='#{leave_room_path(@room.code)}']", count: 0
    @host.post leave_room_path(@room.code)
    @host.assert_response :unprocessable_content
    assert_equal 3, @room.players.count
  end
end
