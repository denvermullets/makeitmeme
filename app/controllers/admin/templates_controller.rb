module Admin
  class TemplatesController < BaseController
    # Hard delete (ADR 0002): the image is purged and Memes keep their baked image with template_id nulled.
    def destroy
      Template.find(params[:id]).destroy!
      redirect_to admin_root_path(q: params[:q].presence), status: :see_other
    end
  end
end
