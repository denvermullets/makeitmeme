# One Upload draft: view and autosave it, and add it to the library. Only the owning browser's token reaches it
# (anyone else gets 404), whatever phase a Room is in.
class UploadDraftsController < ApplicationController
  include RoomSession

  before_action :require_draft

  def show; end

  # Autosave: PATCH JSON { text_boxes, name? }, the same contract as the Admin endpoint.
  def update
    body = request.request_parameters
    result = Upload.save_text_boxes(@draft, body['text_boxes'], name: body['name'])
    if result.valid?
      render json: { text_boxes: @draft.text_boxes, name: @draft.name }
    else
      render json: { errors: result.errors }, status: :unprocessable_content
    end
  end

  def add
    Upload.add_to_library(@draft)
    redirect_to uploaded_path
  rescue ActiveRecord::RecordInvalid => e
    @errors = e.record.errors.full_messages
    render :show, status: :unprocessable_content
  end

  private

  def require_draft
    @draft = UploadDraft.owned_by(browser_token, params[:id])
    head :not_found unless @draft
  end
end
