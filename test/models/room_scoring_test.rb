require 'test_helper'

# Scoring: closing a Meme's vote caches its counts and points, adds them to the maker's total and charges each
# voter who cast nothing; the last vote of the Game also charges every unspent Buddy. Nothing is shown until the
# Round's results.
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
  # Expected [up, meh, down, points] per Meme. Meme points: ada -1, bob -1, cy 1. Missed Votes (-1 each): ada 1,
  # bob 1, cy 2. Unused Buddies (-3 each): 2 each. Totals: ada -8, bob -8, cy -7.
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

  test 'each Buddy adds 3 to the Meme and its maker, and is neither an up nor a meh' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    meme = @room.current_meme
    maker = meme.game_player
    others = %w[ada bob cy] - [maker.player.browser_token]
    others.each { |t| @room.cast_vote(by: @room.player_for(t), meme_id: meme.id, kind: 'buddy') }

    assert_equal [0, 0, 0, 6], counts(meme.reload)
    assert_equal 6, maker.reload.total
  end

  test 'the Buddy count is cached on the Meme when its vote closes, once' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    meme = @room.current_meme
    others = %w[ada bob cy] - [meme.game_player.player.browser_token]
    @room.cast_vote(by: @room.player_for(others.first), meme_id: meme.id, kind: 'buddy')
    @room.cast_vote(by: @room.player_for(others.last), meme_id: meme.id, kind: 'up')

    assert_equal 1, meme.reload.buddy_count
    assert_equal 4, meme.points
    end_phase
    assert_equal [1, 4], [meme.reload.buddy_count, meme.points]
  end

  test 'a Buddy mixes with Votes and a missing Vote is still a meh' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    meme = @room.current_meme
    others = %w[ada bob cy] - [meme.game_player.player.browser_token]
    @room.cast_vote(by: @room.player_for(others.first), meme_id: meme.id, kind: 'buddy')
    end_phase

    assert_equal [0, 1, 0, 3], counts(meme.reload)
  end

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
        if @room.reload.current_meme_id == meme.id
          assert_equal [0, 0, 0, 0], counts(meme.reload), 'nothing is cached before the vote closes'
          end_phase
        end
        assert_equal EXPECTED[index].fetch(maker), counts(meme.reload), "Round #{index + 1} #{maker}"
      end
      assert @room.standings?
      end_phase
    end

    assert @room.scoreboard?
    assert_equal CAST_VOTES, Vote.count, 'no Vote row is written for a missing Vote'
    totals = @room.current_game.game_players.to_h { |gp| [gp.nickname, gp.total] }
    assert_equal({ 'Ada' => -8, 'Bob' => -8, 'Cy' => -7 }, totals)
    missed = @room.current_game.game_players.to_h { |gp| [gp.nickname, [gp.missed_votes, gp.unused_buddies]] }
    assert_equal({ 'Ada' => [1, 2], 'Bob' => [1, 2], 'Cy' => [2, 2] }, missed)
    assert_equal 'Cy', @room.current_game.game_players.order(total: :desc).first.nickname
  end

  test 'a stale or repeated advance never double-counts a Meme or a penalty' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    meme = @room.current_meme
    voter = @room.player_for((%w[ada bob cy] - [meme.game_player.player.browser_token]).first)
    @room.cast_vote(by: voter, meme_id: meme.id, kind: 'up')
    seq = @room.phase_seq
    end_phase
    maker = meme.game_player
    silent = @room.current_game.game_players.where.not(id: [maker.id, @room.game_player_for(voter).id]).sole

    assert_equal 1, maker.reload.total
    assert_equal [-1, 1], [silent.reload.total, silent.missed_votes]
    travel_to(@room.reload.phase_deadline_at + 2.seconds) { assert_not @room.advance!(from_seq: seq) }
    assert_equal 1, maker.reload.total
    assert_equal [-1, 1], [silent.reload.total, silent.missed_votes]
    assert_equal [1, 1, 0, 1], counts(meme.reload)
  end

  def vote_as(token, meme, kind) = @room.cast_vote(by: @room.player_for(token), meme_id: meme.id, kind:)

  # Every eligible voter votes on the Meme under vote (the first `kind`, the rest meh), which closes it early.
  def everyone_votes(kind = 'up')
    meme = @room.reload.current_meme
    voters = %w[ada bob cy] - [meme.game_player.player.browser_token]
    voters.each_with_index { |token, i| vote_as(token, meme, i.zero? ? kind : 'meh') }
    meme
  end

  test 'a Player with no Meme scores 0 for the Round and still votes on the others' do
    submit_memes(@room, 'ada', 'bob')
    end_phase
    cy = @room.player_for('cy').then { |player| @room.game_player_for(player) }
    seen = []
    2.times do
      meme = @room.current_meme
      seen << meme.game_player.player.browser_token
      vote_as('cy', meme, 'up')
      vote_as((%w[ada bob] - [seen.last]).first, meme, 'meh')
      assert_equal 1, meme.reload.up_count, 'the Player with no Meme still voted'
    end
    assert @room.reload.standings?
    end_phase

    assert_equal %w[ada bob], seen.sort
    assert_equal 0, cy.reload.total
    assert_equal 0, Meme.where(game_player: cy).count
    assert @room.reload.captioning?
    assert_equal 2, @room.current_round_number
    totals = @room.current_game.game_players.to_h { |g| [g.nickname, g.total] }
    assert_equal({ 'Ada' => 1, 'Bob' => 1, 'Cy' => 0 }, totals)
  end

  test 'a Round where nobody made a Meme scores nobody and the Game goes on, but unspent Buddies still cost' do
    6.times { end_phase }

    assert @room.scoreboard?
    assert_equal [-6, -6, -6], @room.current_game.game_players.map(&:total)
    assert_equal [0, 0, 0], @room.current_game.game_players.map(&:missed_votes)
    assert_equal 0, Vote.count
  end

  test 'a missing Meme in one Round does not cost the Player in other Rounds' do
    submit_memes(@room, 'ada', 'bob')
    end_phase
    2.times do
      meme = @room.reload.current_meme
      vote_as('cy', meme, 'up')
      vote_as((%w[ada bob] - [meme.game_player.player.browser_token]).first, meme, 'meh')
    end
    end_phase # Standings
    submit_memes(@room, 'ada', 'bob', 'cy')
    3.times { everyone_votes }

    assert @room.reload.standings?
    end_phase
    totals = @room.reload.current_game.game_players.to_h { |g| [g.nickname, g.total] }
    assert_equal({ 'Ada' => 2, 'Bob' => 2, 'Cy' => 1 }, totals)
    assert_equal 3, @room.current_round_number
  end

  test 'a late Player can vote on the current and later Memes but not on one whose vote has closed' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    first = @room.current_meme
    voter = (%w[ada bob cy] - [first.game_player.player.browser_token]).first
    end_phase
    error = assert_raises(ActiveRecord::RecordInvalid) { vote_as(voter, first, 'up') }
    assert_includes error.record.errors.full_messages, 'That is not the Meme being voted on'

    second = @room.current_meme
    late = (%w[ada bob cy] - [second.game_player.player.browser_token]).first
    assert_difference -> { Vote.count }, 1 do
      vote_as(late, second, 'down')
    end
    assert_raises(ActiveRecord::RecordInvalid) { vote_as(late, first, 'up') }
  end

  def seat(token) = @room.game_player_for(@room.player_for(token)).reload

  test 'each voter who casts nothing loses a point and has the miss recorded; the maker and voters are not charged' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    meme = @room.current_meme
    maker = meme.game_player.player.browser_token
    voter, silent = %w[ada bob cy] - [maker]
    vote_as(voter, meme, 'down')
    end_phase

    assert_equal [-1, 1], [seat(silent).total, seat(silent).missed_votes]
    assert_equal [0, 0], [seat(voter).total, seat(voter).missed_votes]
    assert_equal [-1, 0], [seat(maker).total, seat(maker).missed_votes]
  end

  test 'an Away voter is charged for a missed Vote too, and a Spectator never is' do
    submit_memes(@room, 'ada', 'bob', 'cy')
    Room.join(code: @room.code, nickname: 'Dee', browser_token: 'dee')
    meme = @room.current_meme
    voter, away = %w[ada bob cy] - [meme.game_player.player.browser_token]
    @room.player_for(away).update!(away_at: Time.current)
    @room.player_went_away!(@room.player_for(away))
    vote_as(voter, meme, 'up')

    assert_equal 1, seat(away).missed_votes
    assert_equal 3, @room.current_game.game_players.count, 'the Spectator has no seat to charge'
  end

  test 'each Buddy unspent at the end of Round 3 voting costs 3, charged before its results show' do
    4.times { end_phase }
    submit_memes(@room, 'ada', 'bob', 'cy')
    meme = @room.reload.current_meme
    spender = (%w[ada bob cy] - [meme.game_player.player.browser_token]).first
    vote_as(spender, meme, 'buddy')
    end_phase while @room.reload.vote?

    assert @room.standings?
    assert_equal 1, seat(spender).unused_buddies
    (%w[ada bob cy] - [spender]).each { |token| assert_equal 2, seat(token).unused_buddies }
    totals = %w[ada bob cy].to_h { |token| [token, seat(token).total] }
    end_phase
    assert @room.scoreboard?
    assert_equal(totals, %w[ada bob cy].to_h { |token| [token, seat(token).total] }, 'charged once, not again')
  end

  test 'Buddies are not charged before Round 3 ends' do
    end_phase
    assert @room.standings?
    assert_equal [0, 0, 0], @room.current_game.game_players.map(&:unused_buddies)
    assert_equal [0, 0, 0], @room.current_game.game_players.map(&:total)
  end

  test 'a Meme Buddy Redux adds 6 to the Meme and its maker and is counted on its own' do
    4.times { end_phase }
    submit_memes(@room, 'ada', 'bob', 'cy')
    2.times { everyone_votes }
    meme = @room.reload.current_meme
    assert @room.final_meme?
    voter, other = %w[ada bob cy] - [meme.game_player.player.browser_token]
    seat(voter).update!(buddies_left: 0)
    vote_as(voter, meme, 'redux')
    vote_as(other, meme, 'up')

    assert @room.reload.standings?
    assert_equal [1, 0, 0, 7], counts(meme.reload)
    assert_equal [0, 1], [meme.buddy_count, meme.redux_count]
    assert_equal 0, seat(voter).unused_buddies
  end
end
