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
      session.assert_select 'turbo-cable-stream-source', count: 2

      mine = @room.hand_for(@room.players.find_by(nickname:)).template_ids
      editor = session.css_select('#hand [data-controller~="meme-editor"]').first
      dealt = JSON.parse(editor['data-meme-editor-hand-value']).pluck('id')
      assert_equal mine, dealt
    end
  end

  test 'a non-Host pressing Start is refused' do
    @bob.post start_room_path(@room.code)

    @bob.assert_response :unprocessable_content
    assert @room.reload.waiting?
  end

  test 'Start renders disabled with the reason below 10 dealable Templates, enabled at 10' do
    Template.delete_all
    seed_templates(9)
    @host.get room_path(@room.code)
    @host.assert_select "form[action='#{start_room_path(@room.code)}'] [disabled]"
    @host.assert_select '#start-gate-reason', text: 'Turn on Packs with at least 10 Templates'

    seed_templates(1)
    @host.get room_path(@room.code)
    @host.assert_select "form[action='#{start_room_path(@room.code)}'] [disabled]", count: 0
    @host.assert_select '#start-gate-reason', count: 0
  end

  test 'a Start request with 9 dealable Templates is refused with the reason' do
    Template.delete_all
    seed_templates(9)
    @host.post start_room_path(@room.code)

    @host.assert_response :unprocessable_content
    @host.assert_select 'li', text: /Turn on Packs with at least 10 Templates/
    assert @room.reload.waiting?
    assert_equal 0, Game.count
  end

  test 'a Start request with exactly 10 dealable Templates is allowed' do
    Template.delete_all
    seed_templates(10)
    @host.post start_room_path(@room.code)

    @host.assert_redirected_to room_path(@room.code)
    assert @room.reload.captioning?
  end

  test 'hiding a Template just after the page rendered refuses the Start' do
    Template.delete_all
    seed_templates(10)
    @host.get room_path(@room.code)
    Template.first.hide!
    @host.post start_room_path(@room.code)

    @host.assert_response :unprocessable_content
    @host.assert_select 'li', text: /Turn on Packs with at least 10 Templates/
    assert @room.reload.waiting?
  end
end
