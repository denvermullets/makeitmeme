class CreatePlayers < ActiveRecord::Migration[8.1]
  def change
    create_table :players do |t|
      t.references :room, null: false, foreign_key: true
      t.string :browser_token, null: false
      t.string :nickname, null: false
      t.datetime :joined_at, null: false
      t.timestamps
    end

    add_index :players, %i[room_id browser_token], unique: true
    add_index :players, 'room_id, lower(nickname)', unique: true, name: 'index_players_on_room_id_and_lower_nickname'

    add_foreign_key :rooms, :players, column: :host_player_id
  end
end
