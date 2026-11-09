require 'test_helper'

# Play again: the Scoreboard goes back to Waiting, and the next Start deals a fresh Game.
class RoomPlayAgainTest < ActiveSupport::TestCase
  setup do
    @room = room_with_players
    seed_templates(30)
    @ada = @room.player_for('ada')
    @room.start(by: @ada)
    3.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }
  end

  test 'Play again needs 3 present Players' do
    @room.player_for('bob').update!(away_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) { @room.play_again(by: @ada) }
    assert_match(/Need 3 present Players, 2 here/, error.message)
    assert @room.reload.scoreboard?
  end

  test 'the Host sends the Room back to Waiting, forgetting the finished Game' do
    @room.play_again(by: @ada)

    @room.reload
    assert @room.waiting?
    assert_nil @room.current_game
    assert_nil @room.current_round_number
    assert_nil @room.phase_deadline_at
    assert_equal %w[Ada Bob Cy], @room.players.order(:joined_at, :id).map(&:nickname)
  end

  test 'only the Host can play again' do
    assert_raises(ActiveRecord::RecordInvalid) { @room.play_again(by: @room.player_for('bob')) }
    assert @room.reload.scoreboard?
  end

  test 'play again is rejected outside the Scoreboard' do
    @room.play_again(by: @ada)
    assert_raises(ActiveRecord::RecordInvalid) { @room.play_again(by: @ada) }
  end

  test 'the finished Game is left untouched' do
    game = @room.current_game
    game.game_players.first.update!(total: 4)
    counts = [game.rounds.count, game.game_players.count, Hand.count]

    @room.play_again(by: @ada)

    assert game.reload.finished?
    assert_equal counts, [game.rounds.count, game.game_players.count, Hand.count]
    assert_equal 4, game.game_players.first.total
  end

  test 'the next Start creates a new Game with totals at 0' do
    old_game = @room.current_game
    old_game.game_players.each { |game_player| game_player.update!(total: 9) }
    @room.play_again(by: @ada)

    @room.start(by: @ada)

    @room.reload
    assert_not_equal old_game.id, @room.current_game_id
    assert_equal 2, @room.games.count
    assert_equal [0, 0, 0], @room.current_game.game_players.map(&:total)
    assert_equal 1, @room.current_round_number
    assert @room.captioning?
  end
end
