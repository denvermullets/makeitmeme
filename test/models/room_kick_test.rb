require 'test_helper'
require 'turbo/broadcastable/test_helper'

class RoomKickTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @room = room_with_players
    @ada = @room.player_for('ada')
    @bob = @room.player_for('bob')
  end

  test 'the Host kicks a Player in Waiting: slot and nickname freed, activity touched' do
    @room.update_column(:last_activity_at, 1.hour.ago)
    @room.kick(player_id: @bob.id, by: @ada)

    assert_nil @room.players.find_by(id: @bob.id)
    assert_equal 2, @room.players.count
    assert_in_delta Time.current, @room.reload.last_activity_at, 5
    assert_nil @room.player_for('bob')
  end

  test 'a kicked Player can rejoin under any nickname, including the freed one' do
    @room.kick(player_id: @bob.id, by: @ada)

    assert_equal 'Bobby', Room.join(code: @room.code, nickname: 'Bobby', browser_token: 'bob').nickname
    @room.kick(player_id: @room.player_for('bob').id, by: @ada)
    assert_equal 'Bob', Room.join(code: @room.code, nickname: 'Bob', browser_token: 'bob').nickname
  end

  test 'only the Host can kick' do
    cy = @room.player_for('cy')
    assert_raises(ActiveRecord::RecordInvalid) { @room.kick(player_id: cy.id, by: @bob) }
    assert_equal 3, @room.players.count
  end

  test 'the Host cannot kick themselves' do
    assert_raises(ActiveRecord::RecordInvalid) { @room.kick(player_id: @ada.id, by: @ada) }
    assert Player.exists?(@ada.id)
  end

  test 'a Player of another Room cannot be kicked' do
    other = Room.create_with_host(nickname: 'Zed', browser_token: 'zed')
    assert_raises(ActiveRecord::RecordInvalid) { @room.kick(player_id: other.host.id, by: @ada) }
    assert Player.exists?(other.host.id)
  end

  test 'nobody can kick outside Waiting' do
    seed_templates(30)
    @room.start(by: @ada)
    assert_raises(ActiveRecord::RecordInvalid) { @room.kick(player_id: @bob.id, by: @ada) }
    assert Player.exists?(@bob.id)
  end

  test 'a kick in Waiting after a finished Game keeps the game-player row, with the link nullified' do
    seed_templates(30)
    @room.start(by: @ada)
    game_player = @room.current_game.game_players.find_by!(nickname: 'Bob')
    @room.update_columns(phase: 'waiting')
    @room.kick(player_id: @bob.id, by: @ada)

    game_player.reload
    assert_nil game_player.player_id
    assert_equal 'Bob', game_player.nickname
  end

  test 'a kick removes the Player from every list and tells the kicked browser to reload' do
    assert_turbo_stream_broadcasts @room, count: 1 do
      assert_turbo_stream_broadcasts [@room, @bob], count: 1 do
        @room.kick(player_id: @bob.id, by: @ada)
      end
    end
  end
end
