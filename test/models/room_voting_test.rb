require 'test_helper'
require 'turbo/broadcastable/test_helper'

# Voting on Memes: after Captioning each Meme gets a vote and a reveal, one Meme at a time.
class RoomVotingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

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

  def current_meme = @room.reload.current_meme

  def maker_token(meme) = meme.game_player.player.browser_token

  def voter_other_than(meme) = (%w[ada bob cy] - [maker_token(meme)]).first

  def rejected_with(message, &)
    error = assert_raises(ActiveRecord::RecordInvalid, &)
    assert_includes error.record.errors.full_messages, message
  end

  def vote(token, kind = 'up', meme: current_meme)
    @room.cast_vote(by: @room.player_for(token), meme_id: meme.id, kind:)
  end

  test 'the end of Captioning shuffles the Rounds Memes and votes on the first for 15s' do
    memes = submit_memes(@room, 'ada', 'bob', 'cy')

    assert @room.vote?
    assert_equal [0, 1, 2], memes.each(&:reload).map(&:position).sort
    assert_equal 0, @room.current_meme.position
    assert_in_delta 15, @room.phase_deadline_at - @room.updated_at, 0.5
    assert_equal 2, @room.phase_seq
  end

  test 'a game-player with no Meme is not in the order' do
    memes = submit_memes(@room, 'ada', 'cy')
    end_phase

    assert_equal [0, 1], memes.each(&:reload).map(&:position).sort
    assert_equal %w[ada cy], memes.map { |m| maker_token(m) }.sort
  end

  test 'a Round with no Memes skips to the next Round, or to the Scoreboard after Round 3' do
    end_phase
    assert @room.standings?
    end_phase
    assert @room.captioning?
    assert_equal 2, @room.current_round_number

    3.times { end_phase }
    assert @room.scoreboard?
    assert_nil @room.current_meme_id
  end

  test 'each Meme gets a vote then a reveal, then the next Round starts' do
    memes = submit_memes(@room, 'ada', 'bob', 'cy')
    seen = []
    3.times do
      seen << @room.current_meme_id
      assert @room.vote?
      end_phase
      assert @room.reveal?
      assert_equal seen.last, @room.current_meme_id
      assert_in_delta 4, @room.phase_deadline_at - @room.updated_at, 0.5
      end_phase
    end

    assert_equal memes.map(&:id).sort, seen.sort
    assert @room.standings?
    end_phase
    assert @room.captioning?
    assert_equal 2, @room.current_round_number
    assert_nil @room.current_meme_id
  end

  test 'after the last Meme of Round 3 the Room goes to the Scoreboard' do
    4.times { end_phase }
    submit_memes(@room, 'ada')
    3.times { end_phase }

    assert @room.scoreboard?
    assert_nil @room.current_meme_id
  end

  test 'play again clears the current Meme' do
    4.times { end_phase }
    submit_memes(@room, 'ada')
    3.times { end_phase }
    @room.play_again(by: @room.player_for('ada'))

    assert @room.reload.waiting?
    assert_nil @room.current_meme_id
  end

  test 'the deadline job closes a vote' do
    submit_memes(@room, 'ada', 'bob')
    end_phase
    assert_enqueued_with(job: PhaseDeadlineJob, args: [@room.id, 2])
    travel_to(@room.phase_deadline_at + 2.seconds) { PhaseDeadlineJob.perform_now(@room.id, 2) }

    assert @room.reload.reveal?
  end

  test 'a Player votes on someone elses Meme' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    voter = voter_other_than(current_meme)

    assert_difference -> { Vote.count }, 1 do
      vote(voter, 'meh')
    end
    assert_equal 'meh', @room.vote_by(@room.player_for(voter))&.kind
    assert_nil @room.vote_by(@room.player_for(maker_token(current_meme)))
  end

  test 'a Vote arriving after the vote deadline and its grace is rejected, one within the grace is taken' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    meme = current_meme
    deadline = @room.phase_deadline_at
    late, slightly_late = (%w[ada bob cy] - [maker_token(meme)])

    travel_to(deadline + (Room::VOTE_GRACE / 2)) { assert vote(slightly_late) }
    travel_to(deadline + Room::VOTE_GRACE + 1.second) do
      rejected_with('Voting is closed') { vote(late) }
    end
    assert_equal 1, meme.votes.count
  end

  test 'a Vote is rejected outside the vote phase' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    meme = current_meme
    voter = voter_other_than(meme)
    end_phase
    rejected_with('Voting is closed') { vote(voter, meme:) }
  end

  test 'a Vote is rejected from a Player not in the Game' do
    submit_memes(@room, 'ada', 'bob')
    end_phase
    stranger = Player.create!(room: Room.create_with_host(nickname: 'Zed', browser_token: 'zed'),
                              nickname: 'Y', browser_token: 'y', joined_at: Time.current)
    rejected_with('You are not in this Game') do
      @room.cast_vote(by: stranger, meme_id: current_meme.id, kind: 'up')
    end
  end

  test 'a Vote on your own Meme is rejected' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    meme = current_meme
    rejected_with('You cannot vote on your own Meme') { vote(maker_token(meme), meme:) }
  end

  test 'a second Vote is rejected and the first stands' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    voter = voter_other_than(current_meme)
    vote(voter, 'up')
    rejected_with('You already voted') { vote(voter, 'down') }
    assert_equal ['up'], Vote.pluck(:kind)
  end

  test 'a Vote on a Meme other than the current one is rejected' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    other = Meme.where.not(id: current_meme.id).first
    voter = (%w[ada bob cy] - [maker_token(other)]).first
    rejected_with('That is not the Meme being voted on') { vote(voter, meme: other) }
  end

  test 'an unknown kind is rejected' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    assert_raises(ActiveRecord::RecordInvalid) { vote(voter_other_than(current_meme), 'love') }
    assert_equal 0, Vote.count
  end

  test 'a Player spends a Buddy as their Vote on someone elses Meme' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    voter = voter_other_than(current_meme)
    vote(voter, 'buddy')

    assert_equal 'buddy', @room.vote_by(@room.player_for(voter))&.kind
    assert_equal 1, current_meme.votes.count
  end

  test 'a Buddy on your own Meme, after voting, or after the vote closed is refused and writes nothing' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    meme = current_meme
    rejected_with('You cannot vote on your own Meme') { vote(maker_token(meme), 'buddy', meme:) }
    voter = voter_other_than(meme)
    vote(voter, 'up')
    rejected_with('You already voted') { vote(voter, 'buddy', meme:) }
    assert_equal 1, meme.votes.count

    end_phase
    late = (%w[ada bob cy] - [maker_token(meme), voter]).first
    rejected_with('Voting is closed') { vote(late, 'buddy', meme:) }
    assert_equal 1, meme.votes.count
  end

  def buddies_left(token) = @room.game_player_for(@room.player_for(token)).reload.buddies_left

  test 'every game-player starts with 2 Buddies and spending one leaves 1' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    voter = voter_other_than(current_meme)
    assert_equal([2, 2, 2], %w[ada bob cy].map { |t| buddies_left(t) })

    vote(voter, 'buddy')

    assert_equal 1, buddies_left(voter)
  end

  test 'a Buddy is refused with nothing written when none are left, and an up still works' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    meme = current_meme
    voter = voter_other_than(meme)
    @room.game_player_for(@room.player_for(voter)).update!(buddies_left: 0)

    rejected_with('You have no Buddies left') { vote(voter, 'buddy', meme:) }

    assert_equal 0, meme.votes.count
    assert_equal 0, buddies_left(voter)
    vote(voter, 'up', meme:)
    assert_equal 1, meme.votes.count
  end

  test 'a refused Buddy spends nothing, whatever the reason' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    meme = current_meme
    maker = maker_token(meme)
    voter = voter_other_than(meme)

    assert_raises(ActiveRecord::RecordInvalid) { vote(maker, 'buddy', meme:) }
    vote(voter, 'up')
    assert_raises(ActiveRecord::RecordInvalid) { vote(voter, 'buddy', meme:) }
    end_phase
    late = (%w[ada bob cy] - [maker, voter]).first
    assert_raises(ActiveRecord::RecordInvalid) { vote(late, 'buddy', meme:) }

    assert_equal([2, 2, 2], %w[ada bob cy].map { |t| buddies_left(t) })
  end

  test 'Buddies carry across Rounds, and a voter who casts nothing keeps theirs' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    meme = current_meme
    spender = voter_other_than(meme)
    idle = (%w[ada bob cy] - [maker_token(meme), spender]).first
    vote(spender, 'buddy')
    end_phase while @room.vote? || @room.reveal?

    assert @room.captioning?
    assert_equal 1, buddies_left(spender)
    assert_equal 2, buddies_left(idle)
  end

  test 'a Vote reaches only the voters own stream' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    voter = @room.player_for(voter_other_than(current_meme))
    other = @room.players.where.not(id: voter.id).first
    ActionCable.server.pubsub.clear

    assert_turbo_stream_broadcasts [@room, voter], count: 1 do
      assert_no_turbo_stream_broadcasts @room do
        assert_no_turbo_stream_broadcasts [@room, other] do
          vote(voter.browser_token)
        end
      end
    end
  end
end
