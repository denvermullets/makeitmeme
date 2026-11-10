require 'test_helper'

# The Upload operation: Start a draft, Save Text Boxes, Add to library.
class UploadTest < ActiveSupport::TestCase
  test 'starting a draft keeps the image as uploaded and seeds the top and bottom Text Boxes' do
    draft = start_upload_draft(token: 'tok', nickname: ' Pat ', file: 'photo.jpg')

    assert_predicate draft, :persisted?
    assert_equal 'tok', draft.browser_token
    assert_equal 'Pat', draft.credit_nickname
    assert_nil draft.name
    assert_predicate draft.image, :attached?
    assert_equal 'image/jpeg', draft.image.content_type
    assert_equal 2, draft.text_boxes.size
    assert_equal [0.0, 0.8], draft.text_boxes.map { |box| box['y'] }
    assert_equal TextBoxes.check(draft.text_boxes).boxes, draft.text_boxes
  end

  test 'a draft records the checksum of the original bytes and the Room code' do
    draft = start_upload_draft(room_code: 'ABCD')

    assert_equal Digest::SHA256.file(file_fixture('drake.png')).hexdigest, draft.original_checksum
    assert_equal 'ABCD', draft.room_code
  end

  test 'a blank or overlong credit nickname is refused and nothing is stored' do
    ['', '   ', 'x' * (Player::NICKNAME_MAX + 1)].each do |nickname|
      error = assert_raises(ActiveRecord::RecordInvalid) { start_upload_draft(nickname:) }
      assert_match(/nickname/i, error.message)
    end
    assert_equal 0, UploadDraft.count
    assert_equal 0, ActiveStorage::Blob.count
  end

  test 'starting without a file is refused' do
    error = assert_raises(ActiveRecord::RecordInvalid) { start_upload_draft(file: nil) }
    assert_match(/choose/i, error.message)
  end

  test 'saving Text Boxes replaces boxes and name' do
    draft = start_upload_draft
    box = TextBoxes::TOP_AND_BOTTOM.first.merge('color' => 'black')

    result = Upload.save_text_boxes(draft, [box], name: ' Cool cat ')

    assert_predicate result, :valid?
    draft.reload
    assert_equal [box], draft.text_boxes
    assert_equal 'Cool cat', draft.name
  end

  test 'invalid boxes persist nothing and return the TextBoxes errors' do
    draft = start_upload_draft
    original = draft.text_boxes

    result = Upload.save_text_boxes(draft, [{ 'x' => 2 }], name: 'New name')

    assert_not_predicate result, :valid?
    assert_predicate result.errors, :present?
    assert_equal original, draft.reload.text_boxes
    assert_nil draft.name
  end

  test 'a name sent as blank is refused along with the boxes' do
    draft = start_upload_draft

    result = Upload.save_text_boxes(draft, TextBoxes::TOP_AND_BOTTOM, name: ' ')

    assert_includes result.errors, 'Name can\'t be blank'
  end

  test 'saving boxes without a name leaves the name alone' do
    draft = start_upload_draft
    Upload.save_text_boxes(draft, TextBoxes::TOP_AND_BOTTOM, name: 'Kept')
    Upload.save_text_boxes(draft, TextBoxes::TOP_AND_BOTTOM)

    assert_equal 'Kept', draft.reload.name
  end

  test 'adding to the library makes an unreviewed Custom Template and deletes the draft' do
    draft = start_upload_draft(nickname: 'Pat', room_code: 'ABCD')
    Upload.save_text_boxes(draft, TextBoxes::TOP_AND_BOTTOM, name: 'Cool cat')
    checksum = draft.original_checksum

    template = Upload.add_to_library(draft)

    assert_predicate template, :persisted?
    assert_equal 'Cool cat', template.name
    assert_equal 'upload', template.source_kind
    assert_equal Pack.custom, template.pack
    assert_nil template.reviewed_at
    assert_equal TextBoxes::TOP_AND_BOTTOM, template.text_boxes
    assert_match(/\Aupload-\h+\z/, template.memegen_id)
    assert_equal [checksum, 'Pat', 'ABCD'],
                 [template.original_checksum, template.uploader_nickname, template.uploader_room_code]
    assert_predicate template.image, :attached?
    assert_not UploadDraft.exists?(draft.id)
    assert_equal 1, ActiveStorage::Blob.count
  end

  test 'adding to the library without a name is refused and keeps the draft' do
    draft = start_upload_draft

    assert_raises(ActiveRecord::RecordInvalid) { Upload.add_to_library(draft) }
    assert UploadDraft.exists?(draft.id)
    assert_equal 0, Template.count
  end

  test 'adding to the library without Text Boxes is refused' do
    draft = start_upload_draft
    draft.update!(name: 'Named', text_boxes: [])

    error = assert_raises(ActiveRecord::RecordInvalid) { Upload.add_to_library(draft) }
    assert_match(/Text Box/, error.message)
    assert_equal 0, Template.count
  end

  test 'a just-added Template is dealt from a Room with Custom on and not with Custom off' do
    draft = start_upload_draft
    Upload.save_text_boxes(draft, TextBoxes::TOP_AND_BOTTOM, name: 'Cool cat')
    template = Upload.add_to_library(draft)
    room = Room.create_with_host(nickname: 'Ada', browser_token: 'ada')

    assert_includes Template.dealable_for(room), template

    room.update!(off_pack_ids: [Pack.custom.id])
    assert_not_includes Template.dealable_for(room), template
  end

  test 'drafts appear in no Template scope' do
    start_upload_draft

    assert_equal 0, Template.count
    assert_empty Template.needs_review
    assert_empty Template.player_uploads
    assert_empty Pack.dealable_counts
  end
end
