require 'test_helper'

# A Player uploads from the home screen, edits the draft and adds it to the library.
class PlayerUploadTest < ActionDispatch::IntegrationTest
  VALID_BOX = { 'x' => 0.1, 'y' => 0.1, 'w' => 0.5, 'h' => 0.2, 'angle' => 5, 'color' => 'black', 'font' => 'thin' }.freeze

  def upload(file: 'photo.jpg', nickname: 'Pat', session: self)
    type = file.end_with?('.jpg') ? 'image/jpeg' : 'image/png'
    session.post upload_path, params: { nickname:, image: fixture_file_upload(file, type) }
  end

  def draft = UploadDraft.order(:id).last

  def patch_draft(boxes, name: nil, session: self, record: draft)
    body = { text_boxes: boxes }
    body[:name] = name if name
    session.patch upload_draft_path(record), params: body, as: :json
  end

  test 'the home screen links to the Upload page, which asks for a credit name and a picture' do
    get root_path
    assert_select 'a[href=?]', upload_path

    get upload_path
    assert_response :success
    assert_select 'form[enctype="multipart/form-data"]' do
      assert_select 'input[name=nickname][required]'
      assert_select 'input[type=file][name=image]'
    end
  end

  test 'uploading a picture creates a draft with top and bottom boxes and shows the editor for it' do
    upload

    assert_redirected_to upload_draft_path(draft)
    assert_equal 'Pat', draft.credit_nickname
    assert_equal TextBoxes::TOP_AND_BOTTOM, draft.text_boxes
    assert_not_nil cookies[:browser_token]
    assert_equal 0, Template.count

    follow_redirect!
    assert_response :success
    assert_select '[data-text-box-editor][data-controls=phone]' do |editor|
      assert_equal upload_draft_path(draft), editor.first['data-text-box-editor-url-value']
      assert_equal 2, JSON.parse(editor.first['data-text-box-editor-boxes-value']).size
    end
    assert_select 'input[name="template[name]"]'
  end

  test 'a PNG works too and keeps an existing browser token' do
    post rooms_path, params: { nickname: 'Ada' }
    token = cookies[:browser_token]

    upload(file: 'drake.png')

    assert_equal 'image/png', draft.image.content_type
    assert_equal token, cookies[:browser_token]
    assert_equal Player.find_by(nickname: 'Ada').browser_token, draft.browser_token
  end

  test 'a blank or overlong credit nickname is refused with a message and no draft' do
    ['', 'x' * (Player::NICKNAME_MAX + 1)].each do |nickname|
      upload(nickname:)
      assert_response :unprocessable_content
      assert_select '.text-red-600', /nickname/i
    end
    assert_equal 0, UploadDraft.count
  end

  test 'no picture is refused with a message' do
    post upload_path, params: { nickname: 'Pat' }

    assert_response :unprocessable_content
    assert_select '.text-red-600', /Choose/
    assert_equal 0, UploadDraft.count
  end

  test 'autosave replaces the boxes and name and never marks anything reviewed' do
    upload
    patch_draft([VALID_BOX], name: 'Cool cat')

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 'Cool cat', body['name']
    assert_equal 0.1, body['text_boxes'].first['x']
    assert_equal [VALID_BOX.merge('x' => 0.1, 'angle' => 5.0)], draft.reload.text_boxes
    assert_equal 'Cool cat', draft.name
  end

  test 'invalid boxes return 422 with the TextBoxes errors and persist nothing' do
    upload
    patch_draft([VALID_BOX.merge('w' => 2)], name: 'Nope')

    assert_response :unprocessable_content
    assert_predicate JSON.parse(response.body)['errors'], :present?
    assert_equal TextBoxes::TOP_AND_BOTTOM, draft.reload.text_boxes
    assert_nil draft.name
  end

  test 'another browser gets 404 for autosave, add and view' do
    upload
    other = open_session
    other.post upload_path, params: { nickname: 'Eve', image: fixture_file_upload('drake.png', 'image/png') }
    mine = UploadDraft.find_by(credit_nickname: 'Pat')
    stranger = open_session

    patch_draft([VALID_BOX], name: 'Hijack', session: stranger, record: mine)
    stranger.assert_response :not_found
    stranger.post add_upload_draft_path(mine)
    stranger.assert_response :not_found
    stranger.get upload_draft_path(mine)
    stranger.assert_response :not_found
    other.patch upload_draft_path(mine), params: { text_boxes: [VALID_BOX] }, as: :json
    other.assert_response :not_found

    assert_nil mine.reload.name
    assert_equal 0, Template.count
  end

  test 'Add to library is refused without a name' do
    upload
    post add_upload_draft_path(draft)

    assert_response :unprocessable_content
    assert_select '.text-red-600', /name/i
    assert_select '[data-text-box-editor]'
    assert_equal 0, Template.count
    assert UploadDraft.exists?
  end

  test 'Add to library is refused without Text Boxes' do
    upload
    draft.update!(name: 'Named', text_boxes: [])
    post add_upload_draft_path(draft)

    assert_response :unprocessable_content
    assert_equal 0, Template.count
  end

  test 'Add to library creates an unreviewed Custom upload Template, deletes the draft and confirms' do
    upload
    patch_draft([VALID_BOX], name: 'Cool cat')
    post add_upload_draft_path(draft)

    assert_redirected_to uploaded_path
    template = Template.last
    assert_equal ['Cool cat', 'upload', Pack.custom, nil, 'Pat'],
                 [template.name, template.source_kind, template.pack, template.reviewed_at, template.uploader_nickname]
    assert_predicate template.image, :attached?
    assert_equal 0, UploadDraft.count

    follow_redirect!
    assert_response :success
    assert_select 'a[href=?]', root_path
    assert_no_match(/Pat/, response.body)
  end

  test 'the Admin sees the upload under Needs review and Uploads, credited in the inspector' do
    upload
    patch_draft([VALID_BOX], name: 'Cool cat')
    post add_upload_draft_path(draft)
    template = Template.last

    admin = open_session
    admin.sign_in_as_admin
    %w[review uploads].each do |filter|
      admin.get admin_root_path(filter:)
      admin.assert_select "li[data-template='#{template.id}']"
    end
    admin.get admin_root_path(selected: template.id)
    admin.assert_select '[data-inspector-source]', 'Player upload by Pat'
  end

  test 'the inspector adds the Room code when the upload came from a Room' do
    template = seed_templates(1).first
    template.update!(source_kind: 'upload', uploader_nickname: 'Pat', uploader_room_code: 'ABCD')

    sign_in_as_admin
    get admin_root_path(selected: template.id)

    assert_select '[data-inspector-source]', 'Player upload by Pat in Room ABCD'
  end

  test 'a byte-for-byte duplicate of a library image is refused with no draft; re-saved bytes are not' do
    upload(file: 'drake.png')
    patch_draft([VALID_BOX], name: 'Drake')
    post add_upload_draft_path(draft)
    assert_equal 1, Template.where(source_kind: 'upload').count

    stranger = open_session
    assert_no_difference 'UploadDraft.count' do
      upload(file: 'drake.png', session: stranger)
    end
    assert_equal 422, stranger.response.status
    assert_match(/This one(&#39;|')s already in the library/, stranger.response.body)

    assert_difference 'UploadDraft.count', 1 do
      upload(file: 'photo.jpg', session: open_session)
    end
  end

  test 'the second of two drafts of one image is refused on Add to library and kept' do
    upload(file: 'drake.png')
    first = draft
    other = open_session
    upload(file: 'drake.png', session: other)
    second = draft
    patch_draft([VALID_BOX], name: 'One', record: first)
    patch_draft([VALID_BOX], name: 'Two', session: other, record: second)

    post add_upload_draft_path(first)
    other.post add_upload_draft_path(second)

    assert_equal 422, other.response.status
    assert_match(/already in the library/, other.response.body)
    assert UploadDraft.exists?(second.id)
    assert_equal 1, Template.where(source_kind: 'upload').count
  end
end
