# The Upload operation: the lifecycle of a Player upload, from picked file to Template in the Custom Pack.
# Refusals raise ActiveRecord::RecordInvalid carrying the message as a base error (see Rejectable); Text Box
# validation is the shared TextBoxes.check and is returned as a TextBoxes::Result, like Template#update_text_boxes.
#
#   draft = Upload.start(file:, browser_token:, nickname:, room_code: nil)  # => UploadDraft, or raises
#   Upload.save_text_boxes(draft, raw_boxes, name: nil)                     # => TextBoxes::Result (no reviewed_at)
#   Upload.add_to_library(draft, name: nil)                                 # => Template, or raises
module Upload
  module_function

  DUPLICATE = 'This one\'s already in the library'.freeze

  def start(file:, browser_token:, nickname:, room_code: nil)
    draft = UploadDraft.new(browser_token:, credit_nickname: nickname.to_s.strip, room_code: room_code.presence,
                            text_boxes: TextBoxes::TOP_AND_BOTTOM.map(&:dup))
    raise ActiveRecord::RecordInvalid, draft unless draft.valid? # the nickname is checked before the file

    bytes = read(file) || draft.reject!('Choose a JPEG, PNG or WebP image')
    image = screen(draft, bytes)
    draft.original_checksum = Digest::SHA256.hexdigest(bytes)
    format = format_of(image)
    store_image(draft, prepare_image(draft, image, format), format)
    UploadDraft.where(browser_token:).where.not(id: draft.id).find_each(&:destroy) # one open draft per browser
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

  def add_to_library(draft, name: nil)
    draft.name = name.to_s.strip unless name.nil? # kept in memory so a refusal re-renders what the Player typed
    draft.reject!('Give your Template a name') if draft.name.to_s.strip.empty?
    draft.save! if draft.name_changed?
    boxes = TextBoxes.check(draft.text_boxes)
    draft.reject!(boxes.errors.first) unless boxes.valid?
    refuse_duplicate(draft, draft.original_checksum)

    begin
      Template.transaction do
        template = create_template(draft, boxes.boxes)
        # Move the attachment row itself so the image is neither copied nor re-processed, nor purged with the draft.
        draft.image_attachment.update!(record: template)
        draft.reload.destroy!
        template
      end
    rescue ActiveRecord::RecordNotUnique # a racing draft won; the unique index is the backstop
      draft.reject!(DUPLICATE)
    end
  end

  # --- steps ---

  def read(file)
    file.read if file.respond_to?(:read)
  end

  ACCEPTED_FORMATS = %w[jpeg png webp].freeze
  CONTENT_TYPES = { 'jpeg' => 'image/jpeg', 'png' => 'image/png', 'webp' => 'image/webp' }.freeze
  EXTENSIONS = { 'jpeg' => 'jpg', 'png' => 'png', 'webp' => 'webp' }.freeze
  FORMAT_REFUSAL = 'Only JPEG, PNG and WebP images can be uploaded'.freeze
  ANIMATED_REFUSAL = 'Animated images aren\'t supported: upload a still JPEG, PNG or WebP image'.freeze
  UNREADABLE_REFUSAL = 'That image is damaged or can\'t be read: try a different file'.freeze
  MAX_BYTES = 10.megabytes
  MIN_SIDE = 300

  # Decodes the bytes once with libvips and refuses unusable files (size, format, dimensions, animation,
  # duplicates, in that order) with draft.reject!(message). Returns the decoded image; its format, dimensions and
  # page count are the only source of truth: never the filename, declared content type or a hand-parsed header.
  def screen(draft, bytes)
    draft.reject!('That file is over the 10 MB limit') if bytes.bytesize > MAX_BYTES
    image = decode(bytes)
    draft.reject!(FORMAT_REFUSAL) unless image && ACCEPTED_FORMATS.include?(format_of(image))
    if [image.width, image.height].min < MIN_SIDE
      draft.reject!("That image is too small: the shortest side must be at least #{MIN_SIDE}px")
    end
    draft.reject!(ANIMATED_REFUSAL) if pages_of(image) > 1
    refuse_duplicate(draft, Digest::SHA256.hexdigest(bytes)) # last: only for files that are otherwise usable
    image
  end

  # nil when libvips can't read the bytes at all. Pixel errors (truncation) surface when the pixels are used.
  def decode(bytes)
    Vips::Image.new_from_buffer(bytes, '', fail_on: :error)
  rescue Vips::Error
    nil
  end

  def format_of(image)
    image.get('vips-loader')[/\A[a-z]+?(?=load)/] # e.g. "jpegload_buffer" -> "jpeg"
  end

  def pages_of(image)
    image.get_typeof('n-pages').positive? ? image.get('n-pages') : 1
  end

  def refuse_duplicate(draft, checksum)
    draft.reject!(DUPLICATE) if Template.exists?(original_checksum: checksum)
  end

  MAX_SIDE = 2048

  # Returns the bytes to store: the image turned upright, stripped of all metadata, longest side capped at
  # MAX_SIDE (never enlarged), in the format it was uploaded in. The original bytes are not kept.
  def prepare_image(draft, image, format)
    cleaned = ImageProcessing::Vips.source(image).autorot.resize_to_limit(MAX_SIDE, MAX_SIDE)
                                   .saver(strip: true).convert(format).call
    cleaned.binmode.read
  rescue Vips::Error # corrupt data behind valid-looking leading bytes
    draft.reject!(UNREADABLE_REFUSAL)
  ensure
    cleaned&.close!
  end

  # The content type and extension come from the detected format, never from the client.
  def store_image(draft, bytes, format)
    draft.image.attach(io: StringIO.new(bytes), filename: "upload.#{EXTENSIONS.fetch(format)}",
                       content_type: CONTENT_TYPES.fetch(format))
    draft.save!
  end

  def create_template(draft, boxes)
    Template.create!(memegen_id: "upload-#{SecureRandom.hex(8)}", name: draft.name.strip, source_kind: 'upload',
                     pack: Pack.custom, text_boxes: boxes, reviewed_at: nil,
                     original_checksum: draft.original_checksum, uploader_nickname: draft.credit_nickname,
                     uploader_room_code: draft.room_code)
  end

  private_class_method :read, :screen, :decode, :format_of, :pages_of, :refuse_duplicate, :prepare_image,
                       :store_image, :create_template
end
