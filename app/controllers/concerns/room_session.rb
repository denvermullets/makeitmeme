# Finds the live Room by the URL's code and the Player by the browser's signed token cookie.
module RoomSession
  extend ActiveSupport::Concern

  included do
    helper_method :current_room, :current_player if respond_to?(:helper_method)
  end

  private

  def current_room
    @current_room ||= Room.live_by_code(params[:code])
  end

  def current_player
    @current_player ||= current_room&.player_for(browser_token)
  end

  def browser_token = cookies.signed[:browser_token]

  def remember_browser_token(token)
    cookies.permanent.signed[:browser_token] = token
  end

  # 404 for an unknown or expired Room.
  def require_room
    head :not_found unless current_room
  end

  # No seat in the Room: 401 by default, controllers serving pages redirect instead.
  def require_player
    deny_player unless current_player
  end

  def deny_player = head(:unauthorized)

  def deny_player_with_redirect = redirect_to(root_path)
end
