# Loads the Library grid state (search, filter, counts, selection) from params for the admin pages.
module LibraryState
  extend ActiveSupport::Concern

  private

  def load_library(selected: params[:selected])
    @query = params[:q].to_s.strip
    @filter = Template::FILTERS.include?(params[:filter]) ? params[:filter] : 'all'
    searched = Template.named_like(@query)
    @counts = Template::FILTERS.index_with { |key| searched.in_filter(key).count }
    @templates = searched.in_filter(@filter).with_attached_image.order(:name, :id)
    @selected = Template.find_by(id: selected)
  end

  # Query params that keep the Admin's search and filter while selecting a Template.
  def library_params(selected)
    filter = params[:filter] if Template::FILTERS.include?(params[:filter]) && params[:filter] != 'all'
    { q: params[:q].presence, selected:, filter: }
  end
end
