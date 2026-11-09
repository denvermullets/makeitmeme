# A meme image with Text Boxes (x/y/w/h as 0-1 fractions of the image) that Players caption.
class Template < ApplicationRecord
  has_one_attached :image
  has_many :memes, dependent: :nullify
  belongs_to :pack, default: -> { Pack.classics }

  SOURCE_KINDS = %w[memegen upload].freeze
  FILTERS = %w[all review uploads hidden].freeze

  validates :memegen_id, :name, presence: true
  validates :source_kind, inclusion: { in: SOURCE_KINDS }

  scope :needs_review, -> { where(reviewed_at: nil, hidden_at: nil) }
  scope :player_uploads, -> { where(source_kind: 'upload') }
  scope :hidden, -> { where.not(hidden_at: nil) }

  def self.in_filter(key)
    case key.to_s
    when 'review' then needs_review
    when 'uploads' then player_uploads
    when 'hidden' then hidden
    else all
    end
  end

  # The one seam for dealing: the Templates a Room may deal from. Must not reorder or weight results.
  # Narrowed to Templates whose Pack is on for the Room (Rooms store the Packs that are off).
  def self.dealable_for(room)
    scope = where(hidden_at: nil)
    room.off_pack_ids.any? ? scope.where.not(pack_id: room.off_pack_ids) : scope
  end

  def hide!
    update!(hidden_at: Time.current) unless hidden?
  end

  def unhide! = update!(hidden_at: nil)

  # Replaces the ordered Text Boxes from untrusted input. Valid input also marks the Template reviewed;
  # invalid input persists nothing. Returns the TextBoxes::Result.
  def update_text_boxes(raw)
    result = TextBoxes.check(raw)
    update!(text_boxes: result.boxes, reviewed_at: Time.current) if result.valid?
    result
  end

  def hidden? = hidden_at.present?
  def needs_review? = reviewed_at.nil? && hidden_at.nil?
  def upload? = source_kind == 'upload'

  after_destroy { TemplateTombstone.bury(memegen_id) }

  # Case-insensitive partial match on name; LIKE wildcards in the term match literally.
  scope :named_like, lambda { |term|
    term.blank? ? all : where('name ILIKE ?', "%#{sanitize_sql_like(term.to_s.strip)}%")
  }
end
