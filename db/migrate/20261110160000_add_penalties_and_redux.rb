class AddPenaltiesAndRedux < ActiveRecord::Migration[8.1]
  def change
    add_column :game_players, :missed_votes, :integer, default: 0, null: false
    add_column :game_players, :unused_buddies, :integer, default: 0, null: false
    add_column :memes, :redux_count, :integer, default: 0, null: false
  end
end
