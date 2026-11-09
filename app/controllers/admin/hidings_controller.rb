module Admin
  # Hide from Hands: a hidden Template stays in the Library but is never dealt. Existing Hands are untouched.
  class HidingsController < BaseController
    include LibraryState

    before_action :set_template

    def create
      @template.hide!
      redirect_back_to_library
    end

    def destroy
      @template.unhide!
      redirect_back_to_library
    end

    private

    def set_template
      @template = Template.find(params[:template_id])
    end

    def redirect_back_to_library
      redirect_to admin_root_path(library_params(params[:selected].presence)), status: :see_other
    end
  end
end
