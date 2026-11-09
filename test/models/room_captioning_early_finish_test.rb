require 'test_helper'

# Captioning ends early once every present dealt-in Player has submitted (checked under the Room lock).
class RoomCaptioningEarlyFinishTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @room = room_with_players
    seed_templates(30)
    @room.start(by: @room.player_for('ada'))
    @seq = @room.reload.phase_seq
  end

  def go_away(token)
    player = @room.player_for(token)
    player.update!(presence_token: player.presence_token + 1)
    player.go_away!(player.presence_token)
  end

  test 'Captioning advances to Vote when the last present Player submits' do
    submit_memes(@room, 'ada', 'bob')
    assert @room.reload.captioning?

    submit_memes(@room, 'cy')
    assert @room.reload.vote?
    assert_equal 3, @room.current_game.rounds.find_by(number: 1).memes.count
  end

  test 'an Away Player is not waited for' do
    go_away('cy')
    assert @room.reload.captioning?

    submit_memes(@room, 'ada')
    assert @room.reload.captioning?
    submit_memes(@room, 'bob')
    assert @room.reload.vote?
  end

  test 'the last unsubmitted present Player going Away advances Captioning' do
    submit_memes(@room, 'ada', 'bob')
    go_away('cy')

    assert @room.reload.vote?
  end

  test 'a Player going Away who is not the last holdout changes nothing' do
    submit_memes(@room, 'ada')
    go_away('cy')

    assert @room.reload.captioning?
  end

  test 'with nobody present Captioning is left to the timer' do
    go_away('ada')
    go_away('bob')
    go_away('cy')

    assert @room.reload.captioning?
  end

  test 'a Spectator is ignored' do
    dan = Room.join(code: @room.code, nickname: 'Dan', browser_token: 'dan')
    assert @room.spectator?(dan)

    submit_memes(@room, 'ada', 'bob', 'cy')
    assert @room.reload.vote?
  end

  test 'the deadline job left behind does nothing' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    vote_seq = @room.reload.phase_seq

    travel_to(@room.phase_deadline_at + 2.minutes) do
      PhaseDeadlineJob.perform_now(@room.id, @seq)
    end
    assert @room.reload.vote?
    assert_equal vote_seq, @room.phase_seq
  end

  test 'a stale early-finish check after the phase moved on does not advance again' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    seq = @room.reload.phase_seq

    @room.finish_early_if_done!
    assert_equal seq, @room.reload.phase_seq
  end

  test 'a Player removed from the Room does not hold Captioning open' do
    submit_memes(@room, 'ada', 'bob')
    @room.remove_player!(@room.player_for('cy'))
    @room.finish_early_if_done!

    assert @room.reload.vote?
  end
end
