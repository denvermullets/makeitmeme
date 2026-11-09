# A Player leaves the Room (Waiting or Scoreboard only), then lands back on the join page.
class LeavesController < RoomActionController
  def create
    current_room.leave(player: current_player)
    redirect_to root_path
  rescue ActiveRecord::RecordInvalid => e
    @errors = e.record.errors.full_messages
    render 'rooms/show', status: :unprocessable_content
  end
end
