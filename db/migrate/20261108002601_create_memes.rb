class CreateMemes < ActiveRecord::Migration[8.1]
  def change
    create_table :memes do |t|
      t.references :round, null: false, foreign_key: true
      t.references :game_player, null: false, foreign_key: true
      t.references :template, foreign_key: { on_delete: :nullify }
      t.jsonb :caption_texts, null: false, default: []
      t.integer :position
      t.integer :points, null: false, default: 0
      t.integer :up_count, null: false, default: 0
      t.integer :meh_count, null: false, default: 0
      t.integer :down_count, null: false, default: 0
      t.timestamps
    end
    add_index :memes, %i[round_id game_player_id], unique: true
  end
end
