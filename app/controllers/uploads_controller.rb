# The Upload page: pick a picture, get an Upload draft. Outside a Room the Player types a credit nickname.
class UploadsController < ApplicationController
  include RoomSession

  def new
    open_draft = browser_token && params[:new].blank? && UploadDraft.where(browser_token:).order(:id).last
    redirect_to upload_draft_path(open_draft) if open_draft
  end

  def create
    token = browser_token || Player.new_browser_token
    draft = Upload.start(file: params[:image], browser_token: token, nickname: params[:nickname])
    remember_browser_token(token)
    redirect_to upload_draft_path(draft)
  rescue ActiveRecord::RecordInvalid => e
    @nickname = params[:nickname]
    @errors = e.record.errors.full_messages
    render :new, status: :unprocessable_content
  end

  def added; end
end
