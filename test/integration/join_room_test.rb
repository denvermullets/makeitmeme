require 'test_helper'

# Thin check that the web layer joins a Room and remembers the browser.
class JoinRoomTest < ActionDispatch::IntegrationTest
  setup do
    @room = Room.create_with_host(nickname: 'Ada', browser_token: 'host-token')
  end

  test 'the home page offers a join form' do
    get root_path

    assert_select "form[action='#{joins_path}'] input[name=code]"
    assert_select "form[action='#{joins_path}'] input[name=nickname]"
  end

  test 'joining lands on Waiting listing every Player' do
    post joins_path, params: { code: @room.code, nickname: 'Bob' }
    assert_redirected_to room_path(@room.code)

    follow_redirect!
    assert_select '#players li', count: 2
    assert_select '#players li', text: /Bob/
  end

  test 'a returning browser goes straight to Waiting without joining twice' do
    post joins_path, params: { code: @room.code, nickname: 'Bob' }
    post joins_path, params: { code: @room.code, nickname: 'Bob again' }

    assert_redirected_to room_path(@room.code)
    assert_equal 2, @room.players.count
  end

  test 'an existing cookie is reused' do
    post rooms_path, params: { nickname: 'Cy' }
    token_cookie = cookies[:browser_token]
    other = Room.create_with_host(nickname: 'Dee', browser_token: 'dee')

    post joins_path, params: { code: other.code, nickname: 'Cy' }

    assert_equal token_cookie, cookies[:browser_token]
  end

  test 'each failure re-shows the form with its message' do
    post joins_path, params: { code: 'ZZZZ', nickname: 'Bob' }
    assert_response :unprocessable_content
    assert_select 'li', text: 'No live Room with that code'

    post joins_path, params: { code: @room.code, nickname: 'ada' }
    assert_response :unprocessable_content
    assert_select 'li', text: /Nickname has already been taken/

    post joins_path, params: { code: @room.code, nickname: '' }
    assert_response :unprocessable_content
    assert_select 'li', text: /Nickname can't be blank/
  end

  test 'the Waiting page subscribes to the Room stream' do
    post joins_path, params: { code: @room.code, nickname: 'Bob' }
    follow_redirect!

    assert_select 'turbo-cable-stream-source[signed-stream-name]'
  end
end
