# Guards admin routes with the Admin flag in the encrypted session; there are no Admin accounts.
module AdminSession
  extend ActiveSupport::Concern

  included do
    helper_method :admin_signed_in?
    before_action :require_admin
  end

  private

  def admin_signed_in? = session[:admin] == true

  def require_admin
    return if admin_signed_in?

    respond_to do |format|
      format.json { head :unauthorized }
      format.any { redirect_to admin_sign_in_path }
    end
  end
end
