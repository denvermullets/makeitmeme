# One game-player's verdict on one Meme. The voter is stored only to enforce the rules; never shown.
class Vote < ApplicationRecord
  enum :kind, { up: 'up', meh: 'meh', down: 'down' }, validate: true

  belongs_to :meme
  belongs_to :game_player

  # Only the voter's own phone learns the Vote (their private stream), so nobody sees who voted what.
  after_create_commit :broadcast_to_voter

  private

  def broadcast_to_voter
    room = meme.round.game.room
    player = game_player.player
    return unless player

    broadcast_replace_to room, player, target: 'vote_controls', partial: 'votes/controls',
                                       locals: { room:, player: }
  end
end
