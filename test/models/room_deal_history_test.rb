require 'test_helper'

# The Room's deal history: across Games in a Room, the least recently dealt Templates are dealt first.
class RoomDealHistoryTest < ActiveSupport::TestCase
  setup do
    @room = room_with_players
    @ada = @room.player_for('ada')
  end

  def finish_game!
    3.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }
  end

  def round_one_dealt
    @room.reload.current_game.rounds.find_by(number: 1).hands.flat_map(&:template_ids)
  end

  test 'each deal records last_dealt_at for every dealt Template' do
    seed_templates(40)
    freeze_time do
      @room.start(by: @ada)

      dealt = round_one_dealt
      rows = DealHistory.where(room: @room)
      assert_equal dealt.sort, rows.pluck(:template_id).sort
      assert(rows.all? { |row| row.last_dealt_at == Time.current })
    end
  end

  test 'a later deal updates the existing row rather than adding one' do
    seed_templates(30)
    @room.start(by: @ada)
    finish_game!

    assert_equal 30, DealHistory.where(room: @room).count
    assert_operator DealHistory.where(room: @room).maximum(:last_dealt_at), :>, @room.games.first.created_at
  end

  test 'in a second Game, Templates never dealt in the Room come before ones that were' do
    templates = seed_templates(40)
    old_ids = templates.first(30).map(&:id)
    old_ids.each { |id| DealHistory.create!(room: @room, template_id: id, last_dealt_at: 1.day.ago) }

    @room.start(by: @ada)

    assert_equal templates.last(10).map(&:id).sort, (round_one_dealt & templates.last(10).map(&:id)).sort
  end

  test 'among previously dealt Templates the longest ago come first' do
    templates = seed_templates(40)
    templates.each_with_index do |template, i|
      DealHistory.create!(room: @room, template:, last_dealt_at: (i + 1).hours.ago)
    end

    @room.start(by: @ada)

    assert_equal templates.last(30).map(&:id).sort, round_one_dealt.sort
  end

  test 'another Room\'s deal history has no effect' do
    templates = seed_templates(40)
    other = room_with_players
    templates.last(30).each { |template| DealHistory.create!(room: other, template:, last_dealt_at: 1.hour.ago) }
    templates.first(10).each { |template| DealHistory.create!(room: other, template:, last_dealt_at: 1.year.ago) }

    @room.start(by: @ada)

    assert_equal 30, round_one_dealt.uniq.size
    assert_equal 0, DealHistory.where(room: @room).where.not(template_id: round_one_dealt).count
  end

  test 'expiry deletes the deal history and keeps the Games' do
    seed_templates(30)
    @room.start(by: @ada)

    travel_to(3.hours.from_now) { assert @room.expire_if_idle! }

    assert_equal 0, DealHistory.where(room_id: @room.id).count
    assert_equal 1, @room.games.count
  end

  test 'hard-deleting a Template removes its deal history rows' do
    templates = seed_templates(30)
    @room.start(by: @ada)

    assert_difference -> { DealHistory.count }, -1 do
      templates.first.destroy!
    end
  end
end
