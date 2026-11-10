# The Upload page: pick a picture, get an Upload draft. Outside a Room the Player types a credit nickname; from a
# Room (?code=) they are found the usual way and credited with their Room nickname.
class UploadsController < ApplicationController
  include RoomSession

  before_action :render_ended, :require_room, :require_player, :require_between_games,
                if: :room_context?, only: %i[new create]

  def new
    open_draft = browser_token && params[:new].blank? && UploadDraft.where(browser_token:).order(:id).last
    redirect_to upload_draft_path(open_draft) if open_draft
  end

  def create
    token = browser_token || Player.new_browser_token
    draft = Upload.start(file: params[:image], browser_token: token, nickname: credit_nickname,
                         room_code: current_room&.code)
    remember_browser_token(token)
    redirect_to upload_draft_path(draft)
  rescue ActiveRecord::RecordInvalid => e
    @nickname = params[:nickname]
    @errors = e.record.errors.full_messages
    render :new, status: :unprocessable_content
  end

  def added; end

  private

  def room_context? = params[:code].present?

  def credit_nickname = room_context? ? current_player.nickname : params[:nickname]

  def render_ended
    render 'rooms/ended', status: :gone if !current_room && Room.expired_by_code(params[:code])
  end

  # Mid-Round the Player belongs in the Room; only Waiting and Scoreboard allow a new upload.
  def require_between_games
    redirect_to room_path(current_room.code) unless current_room.waiting? || current_room.scoreboard?
  end

  def deny_player = deny_player_with_redirect
end
