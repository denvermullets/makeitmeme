# One Player's captioned Template for one Round: the baked PNG plus the texts it was made from.
class Meme < ApplicationRecord
  include Rejectable

  CAPTION_MAX = 80
  MAX_BYTES = 5.megabytes
  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze

  belongs_to :round
  belongs_to :game_player
  belongs_to :template, optional: true

  has_many :votes, dependent: :destroy

  has_one_attached :image

  # Enter the Player's Meme into the Hand's Round. Raises RecordInvalid when the Template is not in the
  # Hand, they already have one or the uploaded file is not an acceptable PNG. Call under the Room row lock.
  def self.submit(hand:, template_id:, signed_id:, captions:)
    template = hand.template_for(template_id)
    meme = new(round: hand.round, game_player: hand.game_player, template:,
               caption_texts: fit_captions(captions, template&.text_boxes&.length.to_i))
    meme.reject!('That Template is not in your Hand') unless template
    meme.reject!('You already submitted a Meme this Round') if hand.meme
    meme.image.attach(meme.png_blob(signed_id))
    meme.tap(&:save!)
  end

  def self.fit_captions(captions, box_count)
    texts = Array(captions).first(box_count).map { |text| text.to_s.strip.first(CAPTION_MAX) }
    texts + Array.new(box_count - texts.length, '')
  end

  # The maker's total moves by these points. Scoring (MEME-7): up +1, meh 0, down -1; a missing Vote is a meh,
  # so `eligible_voters` (the Game's game-players minus the maker) fills the meh count. Caches the counts and
  # points here. Call once, under the Room row lock, inside the phase_seq-guarded advance.
  def score!(eligible_voters:)
    tally = votes.group(:kind).count
    up = tally.fetch('up', 0)
    down = tally.fetch('down', 0)
    update!(up_count: up, down_count: down, meh_count: eligible_voters - up - down, points: up - down)
    game_player.increment!(:total, points)
  end

  # The Vote this game-player cast on the Meme, or nil.
  def vote_by(voter)
    votes.find_by(game_player: voter) if voter
  end

  # The uploaded blob, once it is shown to be a PNG within the size limit.
  def png_blob(signed_id)
    blob = ActiveStorage::Blob.find_signed(signed_id.to_s)
    reject!('The Meme must be a PNG') unless blob&.content_type == 'image/png' && png_content?(blob)
    reject!("The Meme is too big (max #{MAX_BYTES / 1.megabyte} MB)") if blob.byte_size > MAX_BYTES
    blob
  end

  private

  # The client names the type; the first bytes say what the file is.
  def png_content?(blob)
    blob.service.download_chunk(blob.key, 0..7).b == PNG_SIGNATURE
  rescue StandardError
    false
  end
end
