# A Player's unfinished upload: the image plus its Text Boxes, owned by one browser token. Never a Template, so it
# can't leak into the Library grid, filter counts, Pack counts or dealing. Created and finished only through Upload.
class UploadDraft < ApplicationRecord
  include Rejectable

  has_one_attached :image

  validates :browser_token, presence: true
  validates :credit_nickname, presence: { message: 'Enter a nickname to be credited with' },
                              length: { maximum: Player::NICKNAME_MAX,
                                        message: "Nickname must be at most #{Player::NICKNAME_MAX} characters" }

  # The draft this browser owns, or nil: the only way controllers look one up.
  def self.owned_by(browser_token, id)
    return if browser_token.blank?

    find_by(id:, browser_token:)
  end
end
