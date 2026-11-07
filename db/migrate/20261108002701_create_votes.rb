class CreateVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :votes do |t|
      t.references :meme, null: false, foreign_key: true
      t.references :game_player, null: false, foreign_key: true
      t.string :kind, null: false
      t.timestamps
    end
    add_index :votes, %i[meme_id game_player_id], unique: true
    add_reference :rooms, :current_meme, foreign_key: { to_table: :memes, on_delete: :nullify }
  end
end
