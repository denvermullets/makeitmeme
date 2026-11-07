# The ten Templates dealt to one Player in a Round.
class Hand < ApplicationRecord
  SIZE = 10

  belongs_to :round
  belongs_to :game_player

  # The Meme this Player submitted from this Hand's Round, if any.
  def meme
    Meme.find_by(round_id:, game_player_id:)
  end

  # The Template with this id if it is in the Hand, else nil.
  def template_for(id)
    Template.find_by(id:) if template_ids.include?(id.to_i)
  end

  # The dealt Templates in dealt order, with images preloaded.
  def templates
    by_id = Template.with_attached_image.where(id: template_ids).index_by(&:id)
    template_ids.filter_map { |id| by_id[id] }
  end
end
