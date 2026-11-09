class AddLibraryStateToTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :templates, :source_kind, :string, null: false, default: 'memegen'
    add_column :templates, :reviewed_at, :datetime
    add_column :templates, :hidden_at, :datetime
  end
end
