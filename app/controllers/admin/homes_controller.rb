module Admin
  class HomesController < BaseController
    def show
      @query = params[:q].to_s.strip
      @templates = Template.named_like(@query).with_attached_image.order(:name, :id)
      @selected = Template.find_by(id: params[:selected])
    end
  end
end
