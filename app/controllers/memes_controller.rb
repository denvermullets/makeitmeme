# A Player submits their baked Meme (already direct-uploaded; we get the blob's signed_id).
class MemesController < ApplicationController
  include RoomSession

  before_action :require_room, :require_player

  def create
    meme = current_room.submit_meme(by: current_player, **meme_params)
    render json: { image_url: rails_storage_proxy_path(meme.image) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
  end

  private

  def meme_params
    { signed_id: params[:signed_id], template_id: params[:template_id], captions: Array(params[:captions]) }
  end
end
