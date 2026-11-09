require 'test_helper'
require 'turbo/broadcastable/test_helper'

# At the Captioning deadline the Room extends the deadline once (same phase) so phones can finish uploading.
class RoomUploadGraceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @room = room_with_players
    seed_templates(30)
    @room.start(by: @room.player_for('ada'))
    @deadline = @room.reload.phase_deadline_at
    @grace_ends = @deadline + Room::UPLOAD_GRACE
    clear_enqueued_jobs
  end

  def deadline_job
    PhaseDeadlineJob.perform_now(@room.id, @room.reload.phase_seq)
  end

  def memes_in_round_one = @room.current_game.rounds.find_by!(number: 1).memes.count

  test 'the first deadline job extends the deadline, bumps phase_seq and stays in Captioning' do
    travel_to(@deadline + 1.second) { deadline_job }

    @room.reload
    assert @room.captioning?
    assert_equal 1, @room.current_round_number
    assert_equal 2, @room.phase_seq
    assert_equal @grace_ends.to_i, @room.phase_deadline_at.to_i
  end

  test 'the extension schedules a new deadline job and does not re-send the screen' do
    ActionCable.server.pubsub.clear
    travel_to(@deadline + 1.second) { deadline_job }

    assert_enqueued_with(job: PhaseDeadlineJob, args: [@room.id, 2])
    assert_empty capture_turbo_stream_broadcasts(@room)
    @room.players.each { |player| assert_empty capture_turbo_stream_broadcasts([@room, player]) }
  end

  test 'the first job, now stale, does nothing after the extension' do
    travel_to(@grace_ends + 1.second) do
      deadline_job
      assert_not @room.advance!(from_seq: 1, only_if_due: true)
    end
    assert_equal 2, @room.reload.phase_seq
  end

  test 'the phones keep counting down to the original deadline' do
    travel_to(@deadline + 1.second) { deadline_job }

    assert_equal @deadline.to_i, @room.reload.countdown_deadline_at.to_i
  end

  test 'during the grace Captioning advances as soon as every present Player has a Meme' do
    travel_to(@deadline + 1.second) { deadline_job }
    submit_memes(@room, 'ada', 'bob')
    assert @room.reload.captioning?

    travel_to(@deadline + 2.seconds) { submit_memes(@room, 'cy') }

    assert @room.reload.vote?
    assert_equal 3, memes_in_round_one
  end

  test 'an Away Player does not hold the grace open' do
    travel_to(@deadline + 1.second) { deadline_job }
    @room.player_for('cy').go_away!(@room.player_for('cy').presence_token)
    submit_memes(@room, 'ada', 'bob')

    assert @room.reload.vote?
  end

  test 'when the grace ends Captioning advances with what arrived, and a missing upload is skipped' do
    travel_to(@deadline + 1.second) { deadline_job }
    submit_memes(@room, 'ada')
    travel_to(@grace_ends + 1.second) { deadline_job }

    assert @room.reload.vote?
    assert_equal 1, memes_in_round_one
    assert_equal 3, @room.phase_seq
  end

  test 'the grace is never extended twice' do
    travel_to(@deadline + 1.second) { deadline_job }
    travel_to(@grace_ends + 1.second) { deadline_job }

    assert_equal 2, @room.reload.current_round_number # advanced to the next Round, not extended again
    assert_equal 3, @room.phase_seq
  end

  # Ada's Meme is in, so when Captioning ends the Room goes to the vote. With no Memes at all it would go straight to
  # the next Round's Captioning, where a late upload is a valid Meme of that Round (the server decides the Round).
  test 'an upload after Captioning advanced to the vote is rejected' do
    submit_memes(@room, 'ada')
    travel_to(@deadline + 1.second) { deadline_job }
    travel_to(@grace_ends + 1.second) do
      deadline_job
      assert @room.reload.vote?
      assert_raises(ActiveRecord::RecordInvalid) { submit_memes(@room, 'cy') }
    end
    assert_equal 1, memes_in_round_one
  end

  test 'an upload after the grace ends but before the job ran is rejected' do
    travel_to(@deadline + 1.second) { deadline_job }
    travel_to(@grace_ends + 1.second) do
      assert_raises(ActiveRecord::RecordInvalid) { submit_memes(@room, 'cy') }
    end
  end

  test 'an upload that beats the first deadline job is still taken' do
    travel_to(@deadline + 1.second) { submit_memes(@room, 'cy') }

    assert_equal 1, memes_in_round_one
  end
end
