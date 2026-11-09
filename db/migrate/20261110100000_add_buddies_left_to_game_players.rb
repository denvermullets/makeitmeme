class AddBuddiesLeftToGamePlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :game_players, :buddies_left, :integer, default: 2, null: false
  end
end
