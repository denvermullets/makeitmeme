class CreateTemplateTombstones < ActiveRecord::Migration[8.1]
  def change
    create_table :template_tombstones do |t|
      t.string :memegen_id, null: false
      t.timestamps
    end
    add_index :template_tombstones, :memegen_id, unique: true
  end
end
