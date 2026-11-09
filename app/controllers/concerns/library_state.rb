# Loads the Library grid state (search, filter, counts, selection) from params for the admin pages.
module LibraryState
  extend ActiveSupport::Concern

  private

  def load_library(selected: params[:selected])
    @query = params[:q].to_s.strip
    @filter = filter_param || 'all'
    @pack = Pack.find_by(id: params[:pack])
    searched = Template.named_like(@query)
    searched = searched.where(pack: @pack) if @pack
    @counts = Template::FILTERS.index_with { |key| searched.in_filter(key).count }
    @templates = searched.in_filter(@filter).with_attached_image.order(:name, :id)
    @selected = Template.find_by(id: selected)
  end

  # Query params that keep the Admin's search and filter while selecting a Template.
  def library_params(selected)
    filter = filter_param unless filter_param == 'all'
    { q: params[:q].presence, selected:, filter:, pack: Pack.find_by(id: params[:pack])&.id }
  end

  # The filter key from params when it is a known one, else nil.
  def filter_param
    params[:filter] if Template::FILTERS.include?(params[:filter])
  end
end
