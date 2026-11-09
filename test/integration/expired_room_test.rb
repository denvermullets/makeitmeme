require 'test_helper'

# Opening the code of an expired Room shows the ended page; the code can be reused by a live Room.
class ExpiredRoomTest < ActionDispatch::IntegrationTest
  setup do
    @room = Room.create_with_host(nickname: 'Ada', browser_token: 'ada')
    @room.update_column(:last_activity_at, 3.hours.ago)
    Room.expire_idle!
  end

  test 'a browser that never had a Player sees the ended page, not a join form' do
    get room_path(@room.code)

    assert_response :gone
    assert_select 'h1', text: 'This Room has ended'
    assert_select "form[action='#{joins_path}']", count: 0
    assert_select "a[href='#{root_path}']"
  end

  test 'a browser whose Player was removed by the expiry sees the ended page' do
    post rooms_path, params: { nickname: 'Zed' }
    old = Room.live.last
    old.update_column(:last_activity_at, 3.hours.ago)
    Room.expire_idle!

    get room_path(old.code)

    assert_response :gone
    assert_select 'h1', text: 'This Room has ended'
  end

  test 'the code is matched in any letter case' do
    get room_path(@room.code.downcase)

    assert_response :gone
  end

  test 'a code nobody ever had is still a 404' do
    get room_path('ZZZZ')

    assert_response :not_found
  end

  test 'a new Room can reuse the expired code and then the code resolves to the live Room' do
    fresh = Room.create_with_host(nickname: 'Bea', browser_token: 'bea', codes: [@room.code].each)

    assert_equal @room.code, fresh.code
    assert_equal fresh, Room.live_by_code(@room.code)

    post joins_path, params: { code: @room.code, nickname: 'Cy' }
    follow_redirect!

    assert_response :success
    assert_select '#players li', count: 2
  end

  test 'the live Room wins over the ended page for a shared code' do
    Room.create_with_host(nickname: 'Bea', browser_token: 'bea', codes: [@room.code].each)
    post joins_path, params: { code: @room.code, nickname: 'Cy' }

    get room_path(@room.code)

    assert_response :success
  end

  test 'joining by the expired code says the Room has ended' do
    post joins_path, params: { code: @room.code.downcase, nickname: 'Cy' }

    assert_response :unprocessable_content
    assert_select 'li', text: 'This Room has ended'
  end

  test 'joining by a code nobody had still says there is no live Room' do
    post joins_path, params: { code: 'ZZZZ', nickname: 'Cy' }

    assert_select 'li', text: 'No live Room with that code'
  end
end
