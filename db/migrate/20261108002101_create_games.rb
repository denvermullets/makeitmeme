class CreateGames < ActiveRecord::Migration[8.1]
  def change
    create_table :games do |t|
      t.references :room, null: false, foreign_key: true
      t.string :recap_token, null: false
      t.string :status, null: false, default: 'in_progress'
      t.datetime :finished_at
      t.timestamps
    end
    add_index :games, :recap_token, unique: true

    # ADR 0002: the game-player row outlives its Player, so the link is nullified on delete.
    create_table :game_players do |t|
      t.references :game, null: false, foreign_key: true
      t.references :player, foreign_key: { on_delete: :nullify }
      t.string :nickname, null: false
      t.integer :total, null: false, default: 0
      t.timestamps
    end

    create_table :rounds do |t|
      t.references :game, null: false, foreign_key: true
      t.integer :number, null: false
      t.timestamps
    end
    add_index :rounds, %i[game_id number], unique: true

    create_table :hands do |t|
      t.references :round, null: false, foreign_key: true
      t.references :game_player, null: false, foreign_key: true
      t.integer :template_ids, array: true, null: false, default: []
      t.timestamps
    end
    add_index :hands, %i[round_id game_player_id], unique: true

    add_reference :rooms, :current_game, foreign_key: { to_table: :games }
    add_column :rooms, :current_round_number, :integer
  end
end
