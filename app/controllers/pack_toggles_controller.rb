# The Host turns a Pack on or off for the Room (`on=1|0`, or flips it when omitted).
class PackTogglesController < RoomActionController
  private

  def operation
    on = params[:on].nil? ? nil : params[:on].to_s.in?(%w[1 true])
    current_room.toggle_pack(pack: Pack.find(params[:pack_id]), by: current_player, on:)
  end
end
