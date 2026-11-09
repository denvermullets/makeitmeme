# Counts a Player's open Room pages. Subscribed only from a Player's own Room page (Spectators included);
# Turbo's streams channel has no hooks for this, so presence cannot ride on it.
class RoomPresenceChannel < ApplicationCable::Channel
  def subscribed
    @player = Room.live_by_code(params[:code])&.player_for(browser_token)
    return reject unless @player

    @player.connected!
  end

  def unsubscribed
    @player&.disconnected!
  end
end
