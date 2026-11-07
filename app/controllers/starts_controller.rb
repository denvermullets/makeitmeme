class StartsController < ApplicationController
  def create
    @room = Room.live.find_by(code: params[:code].to_s.upcase)
    return head :not_found unless @room

    @player = @room.player_for(cookies.signed[:browser_token])
    return redirect_to root_path unless @player

    @room.start(by: @player)
    redirect_to room_path(@room.code)
  rescue ActiveRecord::RecordInvalid => e
    @errors = e.record.errors.full_messages
    render 'rooms/show', status: :unprocessable_content
  end
end
