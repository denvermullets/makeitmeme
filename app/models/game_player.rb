# A Player's seat in one Game: a nickname snapshot and the running total. Survives the Player (ADR 0002).
class GamePlayer < ApplicationRecord
  BUDDIES_PER_GAME = 2 # keep in step with the buddies_left column default
  # Penalties come off the voter's own total: each Meme they could vote on but did not, and each Buddy still
  # unspent once the last Meme of the Game has been voted on.
  MISSED_VOTE_PENALTY = 1
  UNUSED_BUDDY_PENALTY = 3

  belongs_to :game
  belongs_to :player, optional: true
  has_many :hands, dependent: :destroy

  # Charges each of these game-players one missed Vote. Call under the Room row lock.
  def self.charge_missed_vote!
    update_all(['missed_votes = missed_votes + 1, total = total - ?', MISSED_VOTE_PENALTY])
  end

  # Charges every unspent Buddy and records how many. Call once, under the Room row lock, after the last vote.
  def charge_unused_buddies!
    update!(unused_buddies: buddies_left, total: total - (UNUSED_BUDDY_PENALTY * buddies_left))
  end
end
