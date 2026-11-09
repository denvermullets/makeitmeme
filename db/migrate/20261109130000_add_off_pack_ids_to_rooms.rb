class AddOffPackIdsToRooms < ActiveRecord::Migration[8.1]
  def change
    add_column :rooms, :off_pack_ids, :bigint, array: true, default: [], null: false
  end
end
