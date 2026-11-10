class RoomsController < ApplicationController
  include RoomSession

  before_action :render_ended, :require_room, :require_player, only: :show

  def new; end

  def create
    token = browser_token || Player.new_browser_token
    room = Room.create_with_host(nickname: params[:nickname].to_s.strip, browser_token: token)
    remember_browser_token(token)
    redirect_to room_path(room.code)
  rescue ActiveRecord::RecordInvalid => e
    @nickname = params[:nickname]
    @errors = e.record.errors.full_messages
    render :new, status: :unprocessable_content
  end

  def show; end

  private

  # No live Room holds the code but an expired one did: say so instead of a bare 404.
  def render_ended
    render :ended, status: :gone if !current_room && Room.expired_by_code(params[:code])
  end

  # A browser without a seat followed the Room's shared link: ask for a nickname, then join.
  def deny_player = render(:join)
end
