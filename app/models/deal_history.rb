# The Room's deal history: when each Template was last dealt in a Room (Game-independent, deleted with the Room's
# Players on expiry, removed when a Template is hard-deleted). Feeds the least-recently-dealt dealing rule.
class DealHistory < ApplicationRecord
  belongs_to :room
  belongs_to :template

  # Upserts last_dealt_at = now for each Template id dealt in the Room.
  def self.record!(room:, template_ids:)
    return if template_ids.empty?

    now = Time.current
    upsert_all(template_ids.uniq.map { |id| { room_id: room.id, template_id: id, last_dealt_at: now } },
               unique_by: %i[room_id template_id], update_only: :last_dealt_at)
  end
end
