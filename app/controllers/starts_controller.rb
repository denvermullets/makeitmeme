class StartsController < RoomActionController
  private

  def operation = current_room.start(by: current_player)
end
