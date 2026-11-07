# A Player taps up / meh / down on the Meme under vote. The result reaches their phone over their private stream.
class VotesController < ApplicationController
  include RoomSession

  before_action :require_room, :require_player

  def create
    current_room.cast_vote(by: current_player, meme_id: params[:meme_id], kind: params[:kind])
    head :no_content
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
  end
end
