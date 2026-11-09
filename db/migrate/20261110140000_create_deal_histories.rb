class CreateDealHistories < ActiveRecord::Migration[8.1]
  def change
    create_table :deal_histories do |t|
      t.references :room, null: false, foreign_key: true
      t.references :template, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :last_dealt_at, null: false
      t.timestamps
    end
    add_index :deal_histories, %i[room_id template_id], unique: true
  end
end
