require 'test_helper'

# MEME-107: the Upload page reached from a Room's Waiting screen and Scoreboard.
class RoomUploadTest < ActionDispatch::IntegrationTest
  setup do
    @room = Room.create_with_host(nickname: 'Ada', browser_token: 'ada-token')
    @bob = open_session
    @bob.post joins_path, params: { code: @room.code, nickname: 'Bob' }
  end

  def upload_from_room(session, code: @room.code)
    session.post upload_path, params: { code:, image: fixture_file_upload('photo.jpg', 'image/jpeg') }
  end

  def add_draft_to_library(draft)
    @bob.patch upload_draft_path(draft), params: { text_boxes: TextBoxes::TOP_AND_BOTTOM, name: 'Mine' }, as: :json
    @bob.post add_upload_draft_path(draft)
  end

  test 'the Waiting screen links to the Upload page for this Room' do
    @bob.get room_path(@room.code)
    @bob.assert_select 'a[href=?]', upload_path(code: @room.code)
  end

  test 'the Scoreboard links to the Upload page for this Room' do
    @room.update!(phase: :scoreboard, current_game: Game.create!(room: @room, status: :finished))
    @bob.get room_path(@room.code)
    @bob.assert_select 'a[href=?]', upload_path(code: @room.code)
  end

  test 'from a Room the Upload page asks for no credit name' do
    @bob.get upload_path(code: @room.code)
    @bob.assert_response :success
    @bob.assert_select 'input[name=nickname]', 0
    @bob.assert_select 'input[type=hidden][name=code][value=?]', @room.code
  end

  test 'uploading from a Room credits the Player nickname and the Room code' do
    upload_from_room(@bob)
    draft = UploadDraft.last

    @bob.assert_redirected_to upload_draft_path(draft)
    assert_equal 'Bob', draft.credit_nickname
    assert_equal @room.code, draft.room_code
  end

  test 'a browser with no seat is redirected like the Room page, an unknown code is 404' do
    stranger = open_session
    stranger.get upload_path(code: @room.code)
    stranger.assert_redirected_to root_path
    upload_from_room(stranger)
    stranger.assert_redirected_to root_path
    assert_equal 0, UploadDraft.count

    stranger.get upload_path(code: 'ZZZZ')
    stranger.assert_response :not_found
  end

  test 'an expired Room behaves like the Room page' do
    @room.update!(expired_at: Time.current)
    @bob.get upload_path(code: @room.code)
    @bob.assert_response :gone
  end

  test 'the draft links back to the Room, and so does the confirmation after Add to library' do
    upload_from_room(@bob)
    draft = UploadDraft.last
    @bob.get upload_draft_path(draft)
    @bob.assert_select 'a[href=?]', room_path(@room.code)

    add_draft_to_library(draft)
    @bob.assert_redirected_to uploaded_path(code: @room.code)
    @bob.follow_redirect!
    @bob.assert_select 'a[href=?]', room_path(@room.code)
  end

  test 'the inspector source line keeps the Room code after the Room expires' do
    upload_from_room(@bob)
    add_draft_to_library(UploadDraft.last)
    @room.update!(expired_at: Time.current)

    sign_in_as_admin
    get admin_root_path(selected: Template.last.id)
    assert_select '[data-inspector-source]', "Player upload by Bob in Room #{@room.code}"
  end
end
