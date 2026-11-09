require 'test_helper'

# A Meme's vote closes early once every present eligible voter has voted.
class RoomVoteEarlyCloseTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @room = room_with_players
    seed_templates(30)
    @room.start(by: @room.player_for('ada'))
    submit_memes(@room, 'ada', 'bob', 'cy') # every present Player submitted: Captioning ends early into the vote
    @room.reload
    clear_enqueued_jobs
  end

  def meme = @room.reload.current_meme

  def author_token = meme.game_player.player.browser_token

  def others = %w[ada bob cy] - [author_token]

  def vote(token, kind = 'up')
    @room.cast_vote(by: @room.player_for(token), meme_id: meme.id, kind:)
  end

  def go_away(token)
    player = @room.player_for(token)
    player.update!(away_at: Time.current)
    @room.player_went_away!(player)
  end

  test 'the vote stays open until every eligible voter has voted, then goes to the reveal' do
    first_meme = meme
    vote(others.first)

    assert @room.reload.vote?
    vote(others.last, 'down')

    assert @room.reload.reveal?
    assert_equal [1, 0, 1], [first_meme.reload.up_count, first_meme.meh_count, first_meme.down_count]
  end

  test 'a Buddy counts as a Vote toward the early close' do
    vote(others.first, 'buddy')
    assert @room.reload.vote?
    vote(others.last)

    assert @room.reload.reveal?
  end

  test 'the Memes author is not waited for' do
    vote(others.first)
    vote(others.last)

    assert_equal 2, meme.votes.count
    assert @room.reload.reveal?
  end

  test 'an Away voter is not waited for and their missing Vote counts as meh' do
    go_away(others.first)

    assert @room.reload.vote?
    vote(others.last)

    assert @room.reload.reveal?
    assert_equal 1, @room.current_meme.votes.count
    assert_equal 1, @room.current_meme.meh_count
  end

  test 'the last voter yet to vote going Away closes the vote straight away' do
    vote(others.first)
    assert @room.reload.vote?

    go_away(others.last)

    assert @room.reload.reveal?
  end

  test 'an Away author does not count and does not stop the vote closing' do
    go_away(author_token)
    vote(others.first)
    vote(others.last)

    assert @room.reload.reveal?
  end

  test 'with every voter Away nothing closes early' do
    others.each { |token| go_away(token) }

    assert @room.reload.vote?
  end

  test 'a Spectator is never waited for' do
    Room.join(code: @room.code, nickname: 'Dee', browser_token: 'dee')
    vote(others.first)
    vote(others.last)

    assert @room.reload.reveal?
  end

  test 'the deadline job left behind does nothing' do
    stale_seq = @room.phase_seq
    vote(others.first)
    vote(others.last)
    reveal_seq = @room.reload.phase_seq

    travel_to(@room.phase_deadline_at - 3.seconds) { PhaseDeadlineJob.perform_now(@room.id, stale_seq) }

    assert_equal reveal_seq, @room.reload.phase_seq
    assert @room.reveal?
  end
end
