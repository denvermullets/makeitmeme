class CreateTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :templates do |t|
      t.string :memegen_id, null: false
      t.string :name, null: false
      t.string :source
      t.jsonb :text_boxes, null: false, default: []
      t.timestamps
    end
    add_index :templates, :memegen_id, unique: true
  end
end
