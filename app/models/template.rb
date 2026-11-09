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
  # Pack on/off narrows this per Room later (MEME-47); `room` is the argument it will use.
  def self.dealable_for(_room)
    where(hidden_at: nil)
  end

  def hide!
    update!(hidden_at: Time.current) unless hidden?
  end

  def unhide! = update!(hidden_at: nil)

  def hidden? = hidden_at.present?
  def needs_review? = reviewed_at.nil? && hidden_at.nil?
  def upload? = source_kind == 'upload'

  after_destroy { TemplateTombstone.bury(memegen_id) }

  # Case-insensitive partial match on name; LIKE wildcards in the term match literally.
  scope :named_like, lambda { |term|
    term.blank? ? all : where('name ILIKE ?', "%#{sanitize_sql_like(term.to_s.strip)}%")
  }
end
