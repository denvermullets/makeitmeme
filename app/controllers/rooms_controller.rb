class RoomsController < ApplicationController
  include RoomSession

  before_action :require_room, :require_player, only: :show

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

  def deny_player = deny_player_with_redirect
end
