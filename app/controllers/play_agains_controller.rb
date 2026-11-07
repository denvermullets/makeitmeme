class PlayAgainsController < RoomActionController
  private

  def operation = current_room.play_again(by: current_player)
end
