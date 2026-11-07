require 'test_helper'

# Thin web checks: each Player is a separate browser session, set up through the real create/join forms.
class StartGameTest < ActionDispatch::IntegrationTest
  setup do
    seed_templates(30)
    @host = open_session
    @host.post rooms_path, params: { nickname: 'Ada' }
    @room = Room.live.last
    @bob = join_session('Bob')
    @cy = join_session('Cy')
  end

  def join_session(nickname)
    open_session.tap { |session| session.post joins_path, params: { code: @room.code, nickname: } }
  end

  test 'only the Host sees Start; others see that we are waiting for the Host' do
    @host.get room_path(@room.code)
    @host.assert_select "form[action='#{start_room_path(@room.code)}']"

    @bob.get room_path(@room.code)
    @bob.assert_select "form[action='#{start_room_path(@room.code)}']", count: 0
    @bob.assert_select 'p', text: /Waiting for the Host/
  end

  test 'starting lands every Player on Captioning showing only their own Hand' do
    @host.post start_room_path(@room.code)
    @host.assert_redirected_to room_path(@room.code)

    @room.reload
    [[@host, 'Ada'], [@bob, 'Bob'], [@cy, 'Cy']].each do |session, nickname|
      session.get room_path(@room.code)
      session.assert_select '#captioning'
      session.assert_select '#hand li', count: 10
      session.assert_select 'turbo-cable-stream-source', count: 2

      mine = @room.hand_for(@room.players.find_by(nickname:)).template_ids
      mine.each { |id| session.assert_select "#hand #template_#{id}" }
      (Template.pluck(:id) - mine).each { |id| session.assert_select "#template_#{id}", count: 0 }
    end
  end

  test 'a non-Host pressing Start is refused' do
    @bob.post start_room_path(@room.code)

    @bob.assert_response :unprocessable_content
    assert @room.reload.waiting?
  end
end
