require 'test_helper'

# The crash backstop: a Room whose deadline job was lost still moves on (ADR 0001).
class SweepOverdueRoomsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @room = room_with_players
    seed_templates(30)
    @room.start(by: @room.player_for('ada'))
    clear_enqueued_jobs # the deadline job is lost
  end

  test 'advances a Room whose deadline passed and whose job never ran' do
    travel_to(91.seconds.from_now) { SweepOverdueRoomsJob.perform_now } # extends the deadline
    travel_to(96.seconds.from_now) { SweepOverdueRoomsJob.perform_now }

    assert @room.reload.standings?
  end

  test 'leaves a Room whose deadline has not passed' do
    SweepOverdueRoomsJob.perform_now

    assert_equal 1, @room.reload.phase_seq
  end

  test 'cannot double-advance with the deadline job' do
    travel_to(96.seconds.from_now) do
      SweepOverdueRoomsJob.perform_now
      PhaseDeadlineJob.perform_now(@room.id, 1)
      SweepOverdueRoomsJob.perform_now
    end

    assert_equal 3, @room.reload.phase_seq # extension, then advance
  end

  test 'ignores expired Rooms and Rooms without a deadline' do
    waiting = room_with_players
    expired = room_with_players
    expired.start(by: expired.player_for('ada'))
    expired.update!(expired_at: Time.current)

    travel_to(96.seconds.from_now) { SweepOverdueRoomsJob.perform_now }

    assert waiting.reload.waiting?
    assert_equal 1, expired.reload.phase_seq
  end

  test 'is scheduled to run often' do
    config = YAML.load_file(Rails.root.join('config/recurring.yml'), aliases: true)
    task = config.values.flat_map(&:values).find { |t| t['class'] == 'SweepOverdueRoomsJob' }

    assert task, 'sweep not in recurring.yml'
    assert_match(/every (\d+ seconds|second)/, task['schedule'])
  end
end
