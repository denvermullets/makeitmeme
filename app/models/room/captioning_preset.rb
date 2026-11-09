# The Host-chosen Captioning length: quick, normal or chill. Stored on the Room, so it carries through Play again.
module Room::CaptioningPreset
  extend ActiveSupport::Concern

  SECONDS = { 'quick' => 60, 'normal' => 90, 'chill' => 150 }.freeze

  included do
    enum :captioning_preset, SECONDS.keys.index_with(&:itself), default: :normal

    after_update_commit :broadcast_captioning_preset!, if: :saved_change_to_captioning_preset?
  end

  # Room game operation: the Host chooses how long Captioning lasts for the next Game.
  # Raises ActiveRecord::RecordInvalid unless the caller is the Host, the Room is in Waiting or on the Scoreboard,
  # and the preset is quick, normal or chill.
  def choose_captioning_preset(preset:, by:)
    with_lock do
      reject!('Only the Host can choose the Captioning length') unless host?(by)
      reject!('The Captioning length can only be changed between Games') unless waiting? || scoreboard?
      reject!('That Captioning preset does not exist') unless SECONDS.key?(preset.to_s)

      update!(captioning_preset: preset.to_s)
      touch_activity!
    end
    self
  end

  # How many seconds this Room's Captioning lasts.
  def captioning_preset_seconds = SECONDS.fetch(captioning_preset)

  # Call after commit: every Player gets their own preset control, one stream each (Host-only buttons).
  def broadcast_captioning_preset!
    players.each do |player|
      broadcast_replace_to self, player, target: 'captioning_preset', partial: 'rooms/captioning_preset',
                                         locals: { room: self, player: }
    end
  end
end
