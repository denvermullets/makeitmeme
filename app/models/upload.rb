# The Upload operation: the lifecycle of a Player upload, from picked file to Template in the Custom Pack.
# Refusals raise ActiveRecord::RecordInvalid carrying the message as a base error (see Rejectable); Text Box
# validation is the shared TextBoxes.check and is returned as a TextBoxes::Result, like Template#update_text_boxes.
#
#   draft = Upload.start(file:, browser_token:, nickname:, room_code: nil)  # => UploadDraft, or raises
#   Upload.save_text_boxes(draft, raw_boxes, name: nil)                     # => TextBoxes::Result (no reviewed_at)
#   Upload.add_to_library(draft)                                            # => Template, or raises
module Upload
  module_function

  # Sibling tickets plug into the marked steps below (screen, prepare_image, library refusals).
  def start(file:, browser_token:, nickname:, room_code: nil)
    draft = UploadDraft.new(browser_token:, credit_nickname: nickname.to_s.strip, room_code: room_code.presence,
                            text_boxes: TextBoxes::TOP_AND_BOTTOM.map(&:dup))
    raise ActiveRecord::RecordInvalid, draft unless draft.valid? # the nickname is checked before the file

    bytes = read(file) || draft.reject!('Choose a JPEG, PNG or WebP image')
    screen(draft, bytes, file)
    draft.original_checksum = Digest::SHA256.hexdigest(bytes)
    store_image(draft, prepare_image(bytes, file), file)
    draft
  end

  def save_text_boxes(draft, raw, name: nil)
    result = TextBoxes.check(raw)
    result = TextBoxes::Result.new([], result.errors + ['Name can\'t be blank']) if !name.nil? && name.to_s.strip.empty?
    return result unless result.valid?

    attrs = { text_boxes: result.boxes }
    attrs[:name] = name.to_s.strip unless name.nil?
    draft.update!(attrs)
    result
  end

  def add_to_library(draft)
    draft.reject!('Give your Template a name') if draft.name.to_s.strip.empty?
    boxes = TextBoxes.check(draft.text_boxes)
    draft.reject!(boxes.errors.first) unless boxes.valid?

    Template.transaction do
      template = create_template(draft, boxes.boxes)
      # Move the attachment row itself so the image is neither copied nor re-processed, nor purged with the draft.
      draft.image_attachment.update!(record: template)
      draft.reload.destroy!
      template
    end
  end

  # --- steps ---

  def read(file)
    file.read if file.respond_to?(:read)
  end

  ACCEPTED_FORMATS = %w[jpeg png].freeze # WebP is added by its own ticket
  FORMAT_REFUSAL = 'Only JPEG, PNG and WebP images can be uploaded'

  # Refuses unusable files (format, size, dimensions, duplicates) with draft.reject!(message).
  def screen(draft, bytes, _file)
    draft.reject!(FORMAT_REFUSAL) unless ACCEPTED_FORMATS.include?(sniff_format(bytes))
  end

  # The real format, from the leading bytes only; never the filename or declared content type.
  def sniff_format(bytes)
    head = bytes.byteslice(0, 12).to_s.b
    return 'jpeg' if head.start_with?("\xFF\xD8\xFF".b)
    return 'png' if head.start_with?("\x89PNG\r\n\x1A\n".b)

    nil
  end

  # Returns the bytes to store: normalisation (orient, strip metadata, cap size) goes here. Stored as uploaded for now.
  def prepare_image(bytes, _file) = bytes

  def store_image(draft, bytes, file)
    draft.image.attach(io: StringIO.new(bytes), filename: file.original_filename, content_type: file.content_type)
    draft.save!
  end

  def create_template(draft, boxes)
    Template.create!(memegen_id: "upload-#{SecureRandom.hex(8)}", name: draft.name.strip, source_kind: 'upload',
                     pack: Pack.custom, text_boxes: boxes, reviewed_at: nil,
                     original_checksum: draft.original_checksum, uploader_nickname: draft.credit_nickname,
                     uploader_room_code: draft.room_code)
  end

  private_class_method :read, :screen, :sniff_format, :prepare_image, :store_image, :create_template
end
