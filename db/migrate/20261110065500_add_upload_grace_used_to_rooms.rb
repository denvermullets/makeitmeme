class AddUploadGraceUsedToRooms < ActiveRecord::Migration[8.1]
  def change
    add_column :rooms, :upload_grace_used, :boolean, default: false, null: false
  end
end
