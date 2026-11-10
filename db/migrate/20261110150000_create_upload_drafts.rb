class CreateUploadDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :upload_drafts do |t|
      t.string :browser_token, null: false
      t.string :credit_nickname, null: false
      t.string :room_code
      t.string :original_checksum, null: false
      t.string :name
      t.jsonb :text_boxes, null: false, default: []
      t.timestamps
    end
    add_index :upload_drafts, :browser_token
    add_index :upload_drafts, :created_at

    add_column :templates, :original_checksum, :string
    add_column :templates, :uploader_nickname, :string
    add_column :templates, :uploader_room_code, :string
    add_index :templates, :original_checksum, unique: true, where: 'original_checksum IS NOT NULL'
  end
end
