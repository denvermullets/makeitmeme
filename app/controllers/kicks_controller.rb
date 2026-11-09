# The Host kicks another Player out of the Room (Waiting only).
class KicksController < RoomActionController
  private

  def operation = current_room.kick(player_id: params[:player_id], by: current_player)
end
