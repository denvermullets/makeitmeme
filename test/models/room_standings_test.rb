require 'test_helper'

# Standings: a 10s shared screen between Rounds 1-2 and the next Captioning, even after a Round with no Memes.
class RoomStandingsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @room = room_with_players
    seed_templates(30)
    @room.start(by: @room.player_for('ada'))
    clear_enqueued_jobs
  end

  def end_phase
    travel_to(@room.reload.phase_deadline_at + 2.seconds) { @room.advance! }
    @room.reload
  end

  def play_round_with_memes
    submit_memes(@room, 'ada', 'bob', 'cy')
    6.times { end_phase }
  end

  test 'after the last reveal of Round 1 the Room is in Standings for 10s, then Round 2 starts with fresh Hands' do
    play_round_with_memes

    assert @room.standings?
    assert_equal 1, @room.current_round_number
    assert_in_delta 10, @room.phase_deadline_at - @room.updated_at, 0.5

    end_phase
    assert @room.captioning?
    assert_equal 2, @room.current_round_number
    assert_equal 10, @room.current_game.rounds.find_by!(number: 2).hands.first.template_ids.size
  end

  test 'the same happens after Round 2, and Round 3 goes straight to the Scoreboard' do
    2.times do
      play_round_with_memes
      assert @room.standings?
      end_phase
    end
    assert_equal 3, @room.current_round_number

    play_round_with_memes
    assert @room.scoreboard?
  end

  test 'a Round 1 or 2 with no Memes still goes through Standings' do
    end_phase
    assert @room.standings?
    assert_nil @room.current_meme_id

    end_phase
    assert @room.captioning?
    assert_equal 2, @room.current_round_number
  end

  test 'a deadline job left from an earlier phase does nothing in Standings' do
    end_phase
    seq = @room.phase_seq

    PhaseDeadlineJob.perform_now(@room.id, seq - 1)

    assert @room.reload.standings?
    assert_equal seq, @room.phase_seq
  end

  test 'a Standings deadline job is scheduled and the sweep advances an overdue Standings' do
    end_phase
    clear_enqueued_jobs

    travel_to(@room.phase_deadline_at + 1.second) { SweepOverdueRoomsJob.perform_now }

    assert @room.reload.captioning?
  end
end
