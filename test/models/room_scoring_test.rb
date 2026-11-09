require 'test_helper'

# Scoring: entering reveal caches the Meme's counts and points and adds them to the maker's total.
class RoomScoringTest < ActiveSupport::TestCase
  setup do
    @room = room_with_players
    seed_templates(30)
    @room.start(by: @room.player_for('ada'))
  end

  # Votes per Round by maker: the other two Players in order (nil = no Vote cast).
  SCRIPT = [
    { 'ada' => %w[up up], 'bob' => %w[down down], 'cy' => ['up', nil] },
    { 'ada' => ['down', nil], 'bob' => %w[up meh], 'cy' => %w[down down] },
    { 'ada' => %w[down down], 'bob' => [nil, nil], 'cy' => %w[up up] }
  ].freeze
  # Expected [up, meh, down, points] per Meme. Totals: ada -1, bob -1, cy 1.
  EXPECTED = [
    { 'ada' => [2, 0, 0, 2], 'bob' => [0, 0, 2, -2], 'cy' => [1, 1, 0, 1] },
    { 'ada' => [0, 1, 1, -1], 'bob' => [1, 1, 0, 1], 'cy' => [0, 0, 2, -2] },
    { 'ada' => [0, 0, 2, -2], 'bob' => [0, 2, 0, 0], 'cy' => [2, 0, 0, 2] }
  ].freeze
  CAST_VOTES = 14

  def end_phase
    travel_to(@room.reload.phase_deadline_at + 2.seconds) { @room.advance! }
    @room.reload
  end

  def counts(meme) = [meme.up_count, meme.meh_count, meme.down_count, meme.points]

  test 'a scripted three-Round Game caches each Meme, each total and the Scoreboard order' do
    SCRIPT.each_with_index do |round_votes, index|
      submit_memes(@room, 'ada', 'bob', 'cy')
      3.times do
        meme = @room.current_meme
        maker = meme.game_player.player.browser_token
        voters = %w[ada bob cy] - [maker]
        round_votes.fetch(maker).each_with_index do |kind, i|
          next unless kind

          @room.cast_vote(by: @room.player_for(voters[i]), meme_id: meme.id, kind:)
        end
        if @room.reload.vote?
          assert_equal [0, 0, 0, 0], counts(meme.reload), 'nothing is cached before the reveal'
          end_phase
        end
        assert @room.reveal?
        assert_equal EXPECTED[index].fetch(maker), counts(meme.reload), "Round #{index + 1} #{maker}"
        end_phase
      end
    end

    assert @room.scoreboard?
    assert_equal CAST_VOTES, Vote.count, 'no Vote row is written for a missing Vote'
    totals = @room.current_game.game_players.to_h { |gp| [gp.nickname, gp.total] }
    assert_equal({ 'Ada' => -1, 'Bob' => -1, 'Cy' => 1 }, totals)
    assert_equal 'Cy', @room.current_game.game_players.order(total: :desc).first.nickname
  end

  test 'a stale or repeated advance never double-counts a reveal' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    meme = @room.current_meme
    voter = @room.player_for((%w[ada bob cy] - [meme.game_player.player.browser_token]).first)
    @room.cast_vote(by: voter, meme_id: meme.id, kind: 'up')
    seq = @room.phase_seq
    end_phase
    maker = meme.game_player

    assert_equal 1, maker.reload.total
    travel_to(@room.reload.phase_deadline_at + 2.seconds) { assert_not @room.advance!(from_seq: seq) }
    assert_equal 1, maker.reload.total
    assert_equal [1, 1, 0, 1], counts(meme.reload)
  end

  def vote_as(token, meme, kind) = @room.cast_vote(by: @room.player_for(token), meme_id: meme.id, kind:)

  test 'a Player with no Meme scores 0 for the Round and still votes on the others' do
    submit_memes(@room, 'ada', 'bob')
    end_phase
    cy = @room.player_for('cy').then { |player| @room.game_player_for(player) }
    seen = []
    2.times do
      meme = @room.current_meme
      seen << meme.game_player.player.browser_token
      vote_as('cy', meme, 'up')
      end_phase
      assert_equal 1, meme.reload.up_count, 'the Player with no Meme still voted'
      end_phase
    end

    assert_equal %w[ada bob], seen.sort
    assert_equal 0, cy.reload.total
    assert_equal 0, Meme.where(game_player: cy).count
    assert @room.reload.captioning?
    assert_equal 2, @room.current_round_number
    totals = @room.current_game.game_players.to_h { |g| [g.nickname, g.total] }
    assert_equal({ 'Ada' => 1, 'Bob' => 1, 'Cy' => 0 }, totals)
  end

  test 'a Round where nobody made a Meme scores nobody and the Game goes on' do
    3.times { end_phase }

    assert @room.scoreboard?
    assert_equal [0, 0, 0], @room.current_game.game_players.map(&:total)
    assert_equal 0, Vote.count
  end

  test 'a missing Meme in one Round does not cost the Player in other Rounds' do
    submit_memes(@room, 'ada', 'bob')
    end_phase
    2.times do
      vote_as('cy', @room.current_meme, 'up')
      end_phase
      end_phase
    end
    submit_memes(@room, 'ada', 'bob', 'cy')
    3.times do
      meme = @room.current_meme
      voter = (%w[ada bob cy] - [meme.game_player.player.browser_token]).first
      vote_as(voter, meme, 'up')
      end_phase
      end_phase
    end

    totals = @room.reload.current_game.game_players.to_h { |g| [g.nickname, g.total] }
    assert_equal({ 'Ada' => 2, 'Bob' => 2, 'Cy' => 1 }, totals)
    assert_equal 3, @room.current_round_number
  end

  test 'a late Player can vote on the current and later Memes but not on one already revealed' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    first = @room.current_meme
    voter = (%w[ada bob cy] - [first.game_player.player.browser_token]).first
    end_phase
    assert @room.reveal?
    error = assert_raises(ActiveRecord::RecordInvalid) { vote_as(voter, first, 'up') }
    assert_includes error.record.errors.full_messages, 'Voting is closed'

    end_phase
    second = @room.current_meme
    late = (%w[ada bob cy] - [second.game_player.player.browser_token]).first
    assert_difference -> { Vote.count }, 1 do
      vote_as(late, second, 'down')
    end
    assert_raises(ActiveRecord::RecordInvalid) { vote_as(late, first, 'up') }
  end
end
