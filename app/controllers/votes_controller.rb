# A Player taps up / meh / down on the Meme under vote. The result reaches their phone over their private stream.
class VotesController < ApplicationController
  def create
    room = Room.live.find_by(code: params[:code].to_s.upcase)
    player = room&.player_for(cookies.signed[:browser_token])
    return head(room ? :unauthorized : :not_found) unless player

    room.cast_vote(by: player, meme_id: params[:meme_id], kind: params[:kind])
    head :no_content
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
  end
end
