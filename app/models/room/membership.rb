# Taking Players out of a Room. `remove_player!` is the one path for every removal (kick now, Leave later):
# it deletes the Player, which frees their slot and nickname, while their game-player rows keep the copied
# nickname and lose the link (DB nullify, ADR 0002).
module Room::Membership
  extend ActiveSupport::Concern

  # A new Player joins (caller holds the lock). A present Player's nickname fails the uniqueness validation ("taken").
  def add_player(nickname:, browser_token:)
    reject!("Room is full (#{Room::MAX_PLAYERS} Players)") if players.count >= Room::MAX_PLAYERS

    players.create!(nickname: nickname.to_s.strip, browser_token:, joined_at: Time.current).tap { touch_activity! }
  end

  # The joining browser takes over the Away Player holding this nickname (trimmed, ignoring case): the Player's
  # browser token is rebound, so the old browser matches no Player. Everything else about the Player is untouched.
  # Returns nil when no Away Player has the nickname (caller holds the lock).
  def take_over_away_player(nickname:, browser_token:)
    away = players.away.find_by('lower(nickname) = ?', nickname.to_s.strip.downcase)
    return unless away

    away.tap { |player| player.update!(browser_token:) }
  end

  # Room game operation: the Host kicks a Player in Waiting. A kick is not a ban: the Player can rejoin under any
  # nickname. Raises ActiveRecord::RecordInvalid unless the caller is the Host, the Room is in Waiting and the
  # target is another Player of this Room.
  def kick(player_id:, by:)
    with_lock do
      reject!('Only the Host can kick Players') unless host?(by)
      reject!('Players can only be kicked in Waiting') unless waiting?

      target = players.find_by(id: player_id) || reject!('No such Player in this Room')
      reject!('The Host cannot kick themselves') if host?(target)

      remove_player!(target)
      touch_activity!
    end
    self
  end

  # Deletes the Player from the Room (caller holds the lock and has already handled the Host role: the Room's
  # host link must not point at the Player). Everyone's Player list drops them, and once committed the removed
  # Player's own browser is told to reload, which lands it on the join form.
  def remove_player!(player)
    player.destroy!
    ActiveRecord.after_all_transactions_commit { broadcast_refresh_to self, player }
  end
end
