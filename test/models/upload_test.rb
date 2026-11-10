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

  def library_ready(draft, name: 'Drake')
    Upload.save_text_boxes(draft, TextBoxes::TOP_AND_BOTTOM, name:)
    draft.reload
  end

  test 'starting a draft of bytes already in the library is refused and no draft is created' do
    Upload.add_to_library(library_ready(start_upload_draft(token: 'a')))

    error = assert_raises(ActiveRecord::RecordInvalid) { start_upload_draft(token: 'b') }
    assert_includes error.record.errors.full_messages, 'This one\'s already in the library'
    assert_equal 0, UploadDraft.count
  end

  test 'of two drafts of the same image the second Add to library is refused and its draft is kept' do
    first = library_ready(start_upload_draft(token: 'a'))
    second = library_ready(start_upload_draft(token: 'b'))
    Upload.add_to_library(first)

    error = assert_raises(ActiveRecord::RecordInvalid) { Upload.add_to_library(second) }
    assert_includes error.record.errors.full_messages, 'This one\'s already in the library'
    assert UploadDraft.exists?(second.id)
    assert_equal 1, Template.where(source_kind: 'upload').count
  end

  test 'deleting the Template frees the image to be uploaded and added again' do
    Upload.add_to_library(library_ready(start_upload_draft(token: 'a'))).destroy!

    template = Upload.add_to_library(library_ready(start_upload_draft(token: 'b')))
    assert_predicate template, :persisted?
  end

  test 'the same picture with different bytes is not blocked' do
    Upload.add_to_library(library_ready(start_upload_draft(token: 'a', file: 'drake.png')))

    assert_predicate start_upload_draft(token: 'b', file: 'photo.jpg'), :persisted?
  end

  test 'a JPEG with an EXIF orientation is stored upright with no orientation left' do
    draft = start_upload_draft(file: 'rotated_gps.jpg')
    stored = stored_image(draft)

    assert_equal [400, 600], [stored.width, stored.height] # fixture is 600x400 flagged "rotate 90"
    assert_includes [0, 1], stored.get('orientation') if stored.get_fields.include?('orientation')
  end

  test 'a JPEG with GPS and other EXIF metadata is stored with none of it' do
    assert_includes stored_image(Vips::Image.new_from_file(file_fixture('rotated_gps.jpg').to_s)).get_fields, 'exif-ifd3-GPSLatitude'

    stored = stored_image(start_upload_draft(file: 'rotated_gps.jpg'))

    assert_empty stored.get_fields.grep(/\Aexif-|\Aicc-|\Axmp-|\Aiptc-|\Aphotoshop-/)
  end

  test 'an image over 2048px is shrunk to 2048 on its longest side keeping its aspect ratio and format' do
    jpeg = stored_image(start_upload_draft(token: 'a', file: 'large.jpg'))
    png = stored_image(start_upload_draft(token: 'b', file: 'large.png'))

    assert_equal [2048, 1024], [jpeg.width, jpeg.height]
    assert_equal [2048, 1024], [png.width, png.height]
    assert_equal %w[image/jpeg image/png], UploadDraft.order(:id).map { |d| d.image.content_type }
    assert_equal %w[jpegload_buffer pngload_buffer],
                 UploadDraft.order(:id).map { |d| Vips::Image.new_from_buffer(d.image.download, '').get('vips-loader') }
  end

  test 'a smaller image keeps its size' do
    stored = stored_image(start_upload_draft(file: 'drake.png'))
    original = Vips::Image.new_from_file(file_fixture('drake.png').to_s)

    assert_equal [original.width, original.height], [stored.width, stored.height]
  end

  test 'the Template made by Add to library carries the cleaned image unchanged' do
    draft = start_upload_draft(file: 'large.jpg')
    cleaned = draft.image.download
    Upload.save_text_boxes(draft, TextBoxes::TOP_AND_BOTTOM, name: 'Big')

    template = Upload.add_to_library(draft)

    assert_equal cleaned, template.image.download
  end

  test 'a static WebP is accepted, normalised and stored as WebP' do
    draft = start_upload_draft(file: 'static.webp')
    stored = stored_image(draft)

    assert_equal 'image/webp', draft.image.content_type
    assert_equal 'webpload_buffer', stored.get('vips-loader')
    assert_equal [400, 400], [stored.width, stored.height]
  end

  test 'a static WebP can be added to the library' do
    draft = start_upload_draft(file: 'static.webp')
    Upload.save_text_boxes(draft, TextBoxes::TOP_AND_BOTTOM, name: 'Orange')

    template = Upload.add_to_library(draft)

    assert_equal 'webpload_buffer', Vips::Image.new_from_buffer(template.image.download, '').get('vips-loader')
  end

  test 'an animated WebP is refused as animated and no draft is created' do
    error = assert_raises(ActiveRecord::RecordInvalid) { start_upload_draft(file: 'animated.webp') }

    assert_match(/animated images aren't supported/i, error.record.errors.full_messages.to_sentence)
    assert_equal 0, UploadDraft.count
  end

  private

  def stored_image(draft_or_image)
    return draft_or_image if draft_or_image.is_a?(Vips::Image)

    Vips::Image.new_from_buffer(draft_or_image.image.download, '')
  end
end
