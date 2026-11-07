require 'test_helper'
require 'turbo/broadcastable/test_helper'

# The Room is a state machine: timed Rounds run themselves to the Scoreboard.
class RoomPhaseEngineTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @room = room_with_players
    seed_templates(30)
    @room.start(by: @room.player_for('ada'))
    clear_enqueued_jobs
    ActionCable.server.pubsub.clear
    @original_seconds = Room.phase_seconds
  end

  teardown { Room.phase_seconds = @original_seconds }

  def run_deadline_job(room = @room)
    PhaseDeadlineJob.perform_now(room.id, room.reload.phase_seq)
  end

  test 'phase durations live in one place and can be changed' do
    assert_equal({ captioning: 90, vote: 15, reveal: 4 }, Room.phase_seconds)
    Room.phase_seconds = Room.phase_seconds.merge(captioning: 5)
    freeze_time do
      @room.advance!
      assert_equal 5.seconds.from_now, @room.reload.phase_deadline_at
    end
  end

  test 'a Captioning deadline in Round 1 deals Round 2 with fresh Hands and a new 90s deadline' do
    bob = @room.player_for('bob')
    old_hand = @room.hand_for(bob)
    travel_to(93.seconds.from_now) do
      run_deadline_job

      @room.reload
      assert @room.captioning?
      assert_equal 2, @room.current_round_number
      assert_equal 2, @room.phase_seq
      assert_equal 90.seconds.from_now.to_i, @room.phase_deadline_at.to_i
      assert_not_equal old_hand.id, @room.hand_for(bob).id
      assert_equal 2, @room.hand_for(bob).game_player.hands.count
      assert_equal 2, @room.current_game.rounds.count
    end
  end

  test 'after Round 3 the Room goes to the Scoreboard with no deadline and the Game is finished' do
    3.times do
      travel_to(@room.reload.phase_deadline_at + 3.seconds) { run_deadline_job }
    end

    @room.reload
    assert @room.scoreboard?
    assert_nil @room.phase_deadline_at
    assert @room.current_game.finished?
    assert @room.current_game.finished_at.present?
  end

  test 'the Scoreboard schedules no further job' do
    2.times { travel_to(@room.reload.phase_deadline_at + 3.seconds) { run_deadline_job } }
    clear_enqueued_jobs
    travel_to(@room.reload.phase_deadline_at + 3.seconds) { run_deadline_job }

    assert_no_enqueued_jobs only: PhaseDeadlineJob
  end

  test 'the job does nothing before the deadline' do
    run_deadline_job
    assert_equal 1, @room.reload.phase_seq
  end

  test 'a job carrying an old phase_seq does nothing' do
    travel_to(93.seconds.from_now) do
      run_deadline_job
      PhaseDeadlineJob.perform_now(@room.id, 1)
      assert_equal 2, @room.reload.phase_seq
    end
  end

  test 'two advances for the same phase_seq move the Room only once' do
    other = Room.find(@room.id)
    assert @room.advance!(from_seq: 1)
    assert_not other.advance!(from_seq: 1)
    assert_equal 2, @room.reload.phase_seq
    assert_equal 2, @room.current_round_number
  end

  test 'a due-only advance (the sweep path) skips a Room whose deadline has not passed' do
    assert_not @room.advance!(from_seq: 1, only_if_due: true)
    travel_to(93.seconds.from_now) { assert @room.advance!(from_seq: 1, only_if_due: true) }
  end

  test 'each transition enqueues one deadline job for the new phase_seq' do
    assert_enqueued_with(job: PhaseDeadlineJob, args: [@room.id, 2]) { @room.advance! }
    assert_enqueued_jobs 1, only: PhaseDeadlineJob
  end

  test 'a rolled back advance enqueues and broadcasts nothing' do
    assert_no_enqueued_jobs only: PhaseDeadlineJob do
      assert_no_turbo_stream_broadcasts @room do
        Room.transaction do
          @room.advance!
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  test 'a transition broadcasts the new screen on the Room stream' do
    assert_turbo_stream_broadcasts @room, count: 1 do
      @room.advance!
    end
  end

  test 'a whole empty Game plays from Start to the Scoreboard through performed jobs' do
    Room.phase_seconds = Room.phase_seconds.merge(captioning: 1)
    room = room_with_players
    room.start(by: room.player_for('ada'))
    3.times do
      travel 4.seconds
      perform_enqueued_jobs(only: PhaseDeadlineJob)
    end

    assert room.reload.scoreboard?
    assert room.current_game.finished?
  end
end
