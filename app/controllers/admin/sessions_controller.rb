module Admin
  class SessionsController < BaseController
    skip_before_action :require_admin, only: %i[new create]

    def new; end

    def create
      if valid_password?(params[:password].to_s)
        reset_session
        session[:admin] = true
        redirect_to admin_root_path
      else
        flash.now[:alert] = 'Wrong password.'
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      reset_session
      redirect_to admin_sign_in_path
    end

    private

    # Constant-time compare; a blank or unset env var never matches.
    def valid_password?(given)
      expected = ENV.fetch('ADMIN_PASSWORD', '')
      return false if expected.blank?

      ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(given),
                                                  Digest::SHA256.hexdigest(expected))
    end
  end
end
