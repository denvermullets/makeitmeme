# Public Recap of a finished Game, keyed by its unguessable recap token. No cookie, no Room session concerns
# (deliberately a plain ApplicationController), reads the Game snapshot only (ADR 0002).
class RecapsController < ApplicationController
  def show
    @game = Game.finished.find_by(recap_token: params[:token].to_s)
    render file: Rails.public_path.join('404.html'), layout: false, status: :not_found unless @game
  end
end
