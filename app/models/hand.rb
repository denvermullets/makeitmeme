# The ten Templates dealt to one Player in a Round.
class Hand < ApplicationRecord
  SIZE = 10

  belongs_to :round
  belongs_to :game_player

  # The dealt Templates in dealt order, with images preloaded.
  def templates
    by_id = Template.with_attached_image.where(id: template_ids).index_by(&:id)
    template_ids.filter_map { |id| by_id[id] }
  end
end
