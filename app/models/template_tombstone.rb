# The memegen id of a deleted Template, so the seed doesn't bring it back.
class TemplateTombstone < ApplicationRecord
  validates :memegen_id, presence: true, uniqueness: true

  def self.bury(memegen_id)
    find_or_create_by!(memegen_id: memegen_id)
  end

  def self.buried?(memegen_id)
    exists?(memegen_id: memegen_id)
  end
end
