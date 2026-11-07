# A Player submits their baked Meme (already direct-uploaded; we get the blob's signed_id).
class MemesController < ApplicationController
  def create
    room = Room.live.find_by(code: params[:code].to_s.upcase)
    player = room&.player_for(cookies.signed[:browser_token])
    return head(room ? :unauthorized : :not_found) unless player

    meme = room.submit_meme(by: player, **submission)
    render json: { image_url: rails_storage_proxy_path(meme.image) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
  end

  private

  def submission
    { signed_id: params[:signed_id], template_id: params[:template_id], captions: Array(params[:captions]) }
  end
end
