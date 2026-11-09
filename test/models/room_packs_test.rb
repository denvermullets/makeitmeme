require 'test_helper'

class RoomPacksTest < ActiveSupport::TestCase
  setup do
    @room = room_with_players
    @host = @room.host
    @pack = Pack.create!(name: 'Spicy')
  end

  test 'every Pack, including one created later, is on for a new Room' do
    seed_templates(2).last.update!(pack: @pack)
    assert_equal 2, Template.dealable_for(@room).count
    later = Pack.create!(name: 'Later')
    Template.first.update!(pack: later)
    assert_equal 2, Template.dealable_for(@room.reload).count
  end

  test 'dealable_for excludes Templates in Packs that are off' do
    a, b = seed_templates(2)
    b.update!(pack: @pack)
    @room.toggle_pack(pack: @pack, by: @host, on: false)
    assert_equal [a.id], Template.dealable_for(@room).pluck(:id)
    @room.toggle_pack(pack: @pack, by: @host, on: true)
    assert_equal 2, Template.dealable_for(@room).count
  end

  test 'toggle without on: flips' do
    @room.toggle_pack(pack: @pack, by: @host)
    assert @room.pack_off?(@pack)
    @room.toggle_pack(pack: @pack, by: @host)
    assert_not @room.pack_off?(@pack)
  end

  test 'a deleted Pack drops out of every off list' do
    @room.toggle_pack(pack: @pack, by: @host, on: false)
    other = room_with_players
    other.toggle_pack(pack: @pack, by: other.host, on: false)
    @pack.destroy!
    assert_empty @room.reload.off_pack_ids
    assert_empty other.reload.off_pack_ids
  end

  test 'only the Host can toggle' do
    assert_raises(ActiveRecord::RecordInvalid) { @room.toggle_pack(pack: @pack, by: @room.player_for('bob'), on: false) }
    assert_empty @room.reload.off_pack_ids
  end

  test 'toggling is refused during a Game' do
    seed_templates
    @room.start(by: @host)
    assert_raises(ActiveRecord::RecordInvalid) { @room.toggle_pack(pack: @pack, by: @host, on: false) }
  end

  test 'toggling is allowed on the Scoreboard and persists into the next Game' do
    seed_templates(12).first(2).each { |t| t.update!(pack: @pack) }
    @room.update!(phase: :scoreboard)
    @room.toggle_pack(pack: @pack, by: @host, on: false)
    @room.update!(phase: :waiting)
    @room.start(by: @host)
    @room.hand_for(@host).template_ids.each { |id| assert_not_equal @pack.id, Template.find(id).pack_id }
  end

  test 'a Hand dealt after toggling only holds Templates from Packs that are on' do
    seed_templates(Hand::SIZE)
    seed_templates(5).each { |t| t.update!(pack: @pack) }
    @room.toggle_pack(pack: @pack, by: @host, on: false)
    @room.start(by: @host)
    @room.players.each do |player|
      ids = @room.hand_for(player).template_ids
      assert_equal [Pack.classics.id], Template.where(id: ids).pluck(:pack_id).uniq
    end
  end

  test 'the Start gate refuses when Packs off leave fewer than 10 dealable' do
    seed_templates(Hand::SIZE).each { |t| t.update!(pack: @pack) }
    @room.toggle_pack(pack: @pack, by: @host, on: false)
    error = assert_raises(ActiveRecord::RecordInvalid) { @room.start(by: @host) }
    assert_match(/dealable Templates/, error.message)
  end
end
