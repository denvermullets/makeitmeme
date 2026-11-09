class AddPresenceToPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :players, :connections_count, :integer, default: 0, null: false
    add_column :players, :presence_token, :integer, default: 0, null: false
    add_column :players, :away_at, :datetime
  end
end
