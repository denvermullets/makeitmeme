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

  BUDDY_POINTS = 3
  # Meme Buddy Redux: offered only on the last Meme of the Game, only to voters with no Buddies left.
  REDUX_POINTS = 2 * BUDDY_POINTS

  # The maker's total moves by these points. Scoring: up +1, meh 0, down -1, each Buddy +3, each Redux +6; a
  # missing Vote is a meh for the maker, so `eligible_voters` (the Game's game-players minus the maker) fills the
  # meh count. Each eligible voter who cast nothing is charged a missed Vote (GamePlayer::MISSED_VOTE_PENALTY).
  # Caches the counts and points here. Call once, under the Room row lock, inside the phase_seq-guarded advance.
  def score!(eligible_voters:)
    tally = votes.group(:kind).count
    up, down, buddy, redux = tally.values_at('up', 'down', 'buddy', 'redux').map(&:to_i)
    update!(up_count: up, down_count: down, buddy_count: buddy, redux_count: redux,
            meh_count: eligible_voters - up - down - buddy - redux,
            points: up - down + (BUDDY_POINTS * buddy) + (REDUX_POINTS * redux))
    game_player.increment!(:total, points)
    silent_voters.charge_missed_vote!
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

  # The Game's game-players, other than the maker, with no Vote on this Meme.
  def silent_voters
    game_player.game.game_players.where.not(id: game_player_id).where.not(id: votes.select(:game_player_id))
  end

  # The client names the type; the first bytes say what the file is.
  def png_content?(blob)
    blob.service.download_chunk(blob.key, 0..7).b == PNG_SIGNATURE
  rescue StandardError
    false
  end
end
