class AddCaptioningPresetToRooms < ActiveRecord::Migration[8.1]
  def change
    add_column :rooms, :captioning_preset, :string, default: 'normal', null: false
  end
end
