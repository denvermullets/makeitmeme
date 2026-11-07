require 'test_helper'

# Thin check that the web layer calls the Room operation and remembers the browser.
class CreateRoomTest < ActionDispatch::IntegrationTest
  test 'creating a Room lands the Host on the Waiting page showing the code' do
    get root_path
    assert_response :success

    post rooms_path, params: { nickname: 'Ada' }
    room = Room.last
    assert_redirected_to room_path(room.code)

    follow_redirect!
    assert_response :success
    assert_select '[data-room-code]', text: room.code
    assert_select '[data-host]', text: /Ada.*Host/m
  end

  test 'reloading the Waiting page shows the same Player and code' do
    post rooms_path, params: { nickname: 'Ada' }
    follow_redirect!
    first = response.body

    get room_path(Room.last.code)

    assert_equal first, response.body
    assert_equal 1, Player.count
  end

  test 'a browser without the cookie cannot act as that Player' do
    post rooms_path, params: { nickname: 'Ada' }
    code = Room.last.code

    reset! # a fresh browser: no cookie
    get room_path(code)

    assert_redirected_to root_path
  end

  test 'a cookie from one Room does not give a seat in another' do
    post rooms_path, params: { nickname: 'Ada' }
    other = Room.create_with_host(nickname: 'Bob', browser_token: 'someone-else')

    get room_path(other.code)

    assert_redirected_to root_path
  end

  test 'a bad nickname re-shows the form with an error and makes no Room' do
    post rooms_path, params: { nickname: 'x' * 17 }

    assert_response :unprocessable_content
    assert_equal 0, Room.count
  end

  test 'an unknown or expired code is a 404' do
    get room_path('ZZZZ')
    assert_response :not_found
  end
end
