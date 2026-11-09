# A themed group of Templates. Every Template belongs to exactly one Pack.
# The Custom Pack is system-owned: it always exists and can't be destroyed.
class Pack < ApplicationRecord
  CUSTOM_NAME = 'Custom'.freeze
  CLASSICS_NAME = 'Classics'.freeze

  has_many :templates, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  before_destroy :keep_custom, prepend: true
  after_destroy :forget_in_rooms
  # Story 63: every open Room sees Pack changes live.
  after_commit -> { Room.broadcast_packs_to_open_rooms }

  scope :alphabetical, -> { order(Arel.sql('lower(packs.name)')) }

  def self.custom
    find_by(custom: true) || create!(name: CUSTOM_NAME, custom: true)
  end

  def self.classics
    where('lower(name) = ?', CLASSICS_NAME.downcase).first || create!(name: CLASSICS_NAME)
  end

  # Dealable (not hidden) Template counts by Pack id, for the Pack list.
  def self.dealable_counts
    Template.not_hidden.group(:pack_id).count
  end

  private

  # Rooms store the Packs that are off; a deleted Pack drops out of every list.
  def forget_in_rooms
    Room.where('? = ANY(off_pack_ids)', id).update_all(['off_pack_ids = array_remove(off_pack_ids, ?)', id])
  end

  def keep_custom
    return unless custom?

    errors.add(:base, 'The Custom Pack cannot be deleted')
    throw :abort
  end
end
