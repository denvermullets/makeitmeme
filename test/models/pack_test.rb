require 'test_helper'

class PackTest < ActiveSupport::TestCase
  test 'names are unique ignoring case' do
    Pack.create!(name: 'Work Memes')

    duplicate = Pack.new(name: 'work memes')

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], 'has already been taken'
  end

  test 'a name is required' do
    assert_not Pack.new(name: ' ').valid?
  end

  test 'Pack.custom is the system-owned Custom Pack and is created on demand, once' do
    custom = Pack.custom

    assert_equal 'Custom', custom.name
    assert custom.custom?
    assert_equal custom, Pack.custom
    assert_equal 1, Pack.where(custom: true).count
  end

  test 'the Custom Pack cannot be destroyed' do
    assert_not Pack.custom.destroy
    assert Pack.exists?(name: 'Custom')
  end

  test 'Pack.classics is an ordinary, deletable Pack' do
    classics = Pack.classics

    assert_equal 'Classics', classics.name
    assert_not classics.custom?
    assert classics.destroy
  end

  test 'a Pack with Templates cannot be destroyed' do
    pack = Pack.create!(name: 'Movies')
    Template.create!(memegen_id: 'x', name: 'X', text_boxes: [], pack: pack)

    assert_not pack.destroy
  end

  test 'every Template belongs to a Pack, defaulting to Classics' do
    template = Template.create!(memegen_id: 'x', name: 'X', text_boxes: [])

    assert_equal Pack.classics, template.pack
    assert_equal [template], Pack.classics.templates.to_a
  end

  test 'the database refuses a Template without a Pack' do
    template = Template.create!(memegen_id: 'x', name: 'X', text_boxes: [])

    assert_raises(ActiveRecord::NotNullViolation) { template.update_columns(pack_id: nil) }
  end
end

class PackMigrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  test 'migrating up creates Custom and Classics and backfills existing Templates into Classics' do
    require Rails.root.join('db/migrate/20261109000100_create_packs.rb')
    migration = CreatePacks.new
    ActiveRecord::Migration.suppress_messages do
      migration.migrate(:down)
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        INSERT INTO templates (memegen_id, name, text_boxes, created_at, updated_at)
        VALUES ('old', 'Old', '[]', now(), now())
      SQL
      migration.migrate(:up)
    end
    Template.reset_column_information
    Pack.reset_column_information

    assert_equal %w[Classics Custom], Pack.order(:name).pluck(:name)
    assert Pack.find_by!(name: 'Custom').custom?
    assert_equal 'Classics', Template.find_by!(memegen_id: 'old').pack.name
  end
end
