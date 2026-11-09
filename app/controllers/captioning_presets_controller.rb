# The Host chooses the Captioning preset (`preset=quick|normal|chill`).
class CaptioningPresetsController < RoomActionController
  private

  def operation
    current_room.choose_captioning_preset(preset: params[:preset], by: current_player)
  end
end
