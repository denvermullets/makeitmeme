class AddBuddyCountToMemes < ActiveRecord::Migration[8.1]
  def change
    add_column :memes, :buddy_count, :integer, default: 0, null: false
  end
end
