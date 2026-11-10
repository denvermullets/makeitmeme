class JoinsController < ApplicationController
  include RoomSession

  def create
    token = browser_token || Player.new_browser_token
    player = Room.join(code: param(:code), nickname: param(:nickname), browser_token: token)
    remember_browser_token(token)
    redirect_to room_path(player.room.code)
  rescue ActiveRecord::RecordInvalid => e
    render_rejection(e.record.errors.full_messages)
  end

  private

  def param(key)
    params[key].to_s.strip
  end

  def render_rejection(errors)
    @code = params[:code]
    @nickname = params[:nickname]
    @errors = errors
    # Came from a live Room's link: stay on its nickname form rather than the home page.
    render(current_room ? 'rooms/join' : 'rooms/new', status: :unprocessable_content)
  end
end
