class CreatePacks < ActiveRecord::Migration[8.1]
  def up
    create_table :packs do |t|
      t.string :name, null: false
      t.boolean :custom, null: false, default: false
      t.timestamps
    end
    add_index :packs, 'lower(name)', unique: true, name: 'index_packs_on_lower_name'
    add_index :packs, :custom, unique: true, where: 'custom', name: 'index_packs_on_single_custom'

    execute "INSERT INTO packs (name, custom, created_at, updated_at) VALUES ('Custom', true, now(), now())"
    execute "INSERT INTO packs (name, custom, created_at, updated_at) VALUES ('Classics', false, now(), now())"

    add_reference :templates, :pack, foreign_key: true
    execute "UPDATE templates SET pack_id = (SELECT id FROM packs WHERE name = 'Classics')"
    change_column_null :templates, :pack_id, false
  end

  def down
    remove_reference :templates, :pack, foreign_key: true
    drop_table :packs
  end
end
