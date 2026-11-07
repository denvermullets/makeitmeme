# A page-posting Room operation (Start, Play again): run it as the current Player, then back to the Room page.
# Subclasses define `operation`; a refusal shows its reasons on the Room page.
class RoomActionController < ApplicationController
  include RoomSession

  before_action :require_room, :require_player

  def create
    operation
    redirect_to room_path(current_room.code)
  rescue ActiveRecord::RecordInvalid => e
    @errors = e.record.errors.full_messages
    render 'rooms/show', status: :unprocessable_content
  end

  private

  def deny_player = deny_player_with_redirect
end
