# A Player leaves the Room (Waiting or Scoreboard only), then lands back on the join page.
class LeavesController < RoomActionController
  private

  def operation = current_room.leave(player: current_player)

  def landing_path = root_path
end
