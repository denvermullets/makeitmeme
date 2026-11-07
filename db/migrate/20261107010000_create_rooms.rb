class CreateRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :rooms do |t|
      t.string :code, null: false
      t.bigint :host_player_id
      t.string :phase, null: false, default: 'waiting'
      t.integer :phase_seq, null: false, default: 0
      t.datetime :phase_deadline_at
      t.datetime :last_activity_at, null: false
      t.datetime :expired_at
      t.timestamps
    end

    # Codes only need to be unique among live Rooms; an expired Room frees its code.
    add_index :rooms, :code, unique: true, where: 'expired_at IS NULL', name: 'index_rooms_on_code_live'
  end
end
