require 'test_helper'
require 'turbo/broadcastable/test_helper'

class RoomLeaveTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    travel_to Time.zone.parse('2026-11-09 12:00')
    @room = Room.create_with_host(nickname: 'Ada', browser_token: 'ada')
    travel 1.minute
    Room.join(code: @room.code, nickname: 'Bob', browser_token: 'bob')
    travel 1.minute
    Room.join(code: @room.code, nickname: 'Cy', browser_token: 'cy')
    @room.reload
  end

  teardown { travel_back }

  def go_away(token)
    player = @room.player_for(token)
    player.connected!
    player.disconnected!
    travel Player::AWAY_GRACE + 1.second
    perform_enqueued_jobs(only: PresenceGraceJob)
  end

  def host_token = @room.reload.host&.browser_token

  test 'leaving in Waiting deletes the Player, frees the slot and nickname, and touches activity' do
    @room.update_column(:last_activity_at, 1.hour.ago)
    @room.leave(player: @room.player_for('bob'))

    assert_nil @room.player_for('bob')
    assert_equal 2, @room.players.count
    assert_in_delta Time.current, @room.reload.last_activity_at, 5
    assert_equal 'Bob', Room.join(code: @room.code, nickname: 'Bob', browser_token: 'bob2').nickname
  end

  test 'a non-Host leaving leaves the Host alone' do
    @room.leave(player: @room.player_for('bob'))
    assert_equal 'ada', host_token
  end

  test 'the Host leaving hands off to the earliest-joined present Player' do
    @room.leave(player: @room.player_for('ada'))
    assert_equal 'bob', host_token
  end

  test 'the Host leaving skips Away Players while someone is present' do
    go_away('bob')
    @room.reload.leave(player: @room.player_for('ada'))
    assert_equal 'cy', host_token
  end

  test 'the Host leaving with everyone else Away falls to the earliest-joined remaining Player' do
    go_away('cy')
    go_away('bob')
    @room.reload.leave(player: @room.player_for('ada'))
    assert_equal 'bob', host_token
  end

  test 'the last Player leaving leaves the Room with no Host' do
    @room.leave(player: @room.player_for('bob'))
    @room.leave(player: @room.player_for('cy'))
    @room.leave(player: @room.reload.player_for('ada'))
    assert_nil host_token
    assert_equal 0, @room.players.count
  end

  test 'leaving is allowed on the Scoreboard' do
    seed_templates(30)
    @room.start(by: @room.player_for('ada'))
    @room.update_columns(phase: 'scoreboard')
    @room.leave(player: @room.player_for('bob'))
    assert_nil @room.player_for('bob')
  end

  test 'leaving is rejected in every Game phase' do
    seed_templates(30)
    @room.start(by: @room.player_for('ada'))
    %w[captioning reveal vote].each do |phase|
      @room.update_columns(phase:)
      assert_raises(ActiveRecord::RecordInvalid) { @room.reload.leave(player: @room.player_for('bob')) }
      assert @room.player_for('bob')
    end
  end

  test 'the leaver keeps their game-player row with the nickname and no Player link' do
    seed_templates(30)
    @room.start(by: @room.player_for('ada'))
    game_player = @room.current_game.game_players.find_by!(nickname: 'Bob')
    @room.update_columns(phase: 'scoreboard')
    @room.leave(player: @room.player_for('bob'))

    game_player.reload
    assert_nil game_player.player_id
    assert_equal 'Bob', game_player.nickname
    assert_includes @room.current_game.game_players.pluck(:nickname), 'Bob'
  end

  test 'Player lists update everywhere, the leaver reloads, and a new Host gets controls' do
    cy = @room.player_for('cy')
    bob = @room.player_for('bob')
    ActionCable.server.pubsub.clear
    @room.leave(player: @room.player_for('ada'))

    assert_not_empty capture_turbo_stream_broadcasts(@room)
    assert_not_empty capture_turbo_stream_broadcasts([@room, cy])
    assert_includes capture_turbo_stream_broadcasts([@room, bob]).map(&:to_html).join, 'start_gate'
  end
end
