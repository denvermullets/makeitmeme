class RoomsController < ApplicationController
  def new; end

  def create
    token = browser_token || Player.new_browser_token
    room = Room.create_with_host(nickname: params[:nickname].to_s.strip, browser_token: token)
    cookies.permanent.signed[:browser_token] = token
    redirect_to room_path(room.code)
  rescue ActiveRecord::RecordInvalid => e
    @nickname = params[:nickname]
    @errors = e.record.errors.full_messages
    render :new, status: :unprocessable_content
  end

  def show
    @room = Room.live.find_by(code: params[:code].to_s.upcase)
    return head :not_found unless @room

    @player = @room.player_for(browser_token)
    redirect_to root_path unless @player
  end

  private

  def browser_token
    cookies.signed[:browser_token]
  end
end
