# A meme image with Text Boxes (x/y/w/h as 0-1 fractions of the image) that Players caption.
class Template < ApplicationRecord
  has_one_attached :image
  belongs_to :pack, default: -> { Pack.classics }

  validates :memegen_id, :name, presence: true

  # Case-insensitive partial match on name; LIKE wildcards in the term match literally.
  scope :named_like, lambda { |term|
    term.blank? ? all : where('name ILIKE ?', "%#{sanitize_sql_like(term.to_s.strip)}%")
  }
end
