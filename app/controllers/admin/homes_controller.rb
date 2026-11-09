module Admin
  class HomesController < BaseController
    def show
      @query = params[:q].to_s.strip
      @filter = Template::FILTERS.include?(params[:filter]) ? params[:filter] : 'all'
      searched = Template.named_like(@query)
      @counts = Template::FILTERS.index_with { |key| searched.in_filter(key).count }
      @templates = searched.in_filter(@filter).with_attached_image.order(:name, :id)
      @selected = Template.find_by(id: params[:selected])
    end
  end
end
