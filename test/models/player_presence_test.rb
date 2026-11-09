require 'test_helper'

class PlayerPresenceTest < ActiveSupport::TestCase
  setup do
    @player = room_with_players.player_for('bob')
  end

  test 'a new Player has no connections' do
    assert_equal 0, @player.connections_count
    assert_nil @player.away_at
  end

  test 'connected! counts connections and bumps the presence token each time' do
    @player.connected!
    token = @player.reload.presence_token
    @player.connected!

    assert_equal 2, @player.reload.connections_count
    assert_operator @player.presence_token, :>, token
  end

  test 'disconnected! lowers the count but never below zero' do
    @player.connected!
    @player.disconnected!
    @player.disconnected!

    assert_equal 0, @player.reload.connections_count
  end

  test 'works from a stale copy of the Player' do
    stale = Player.find(@player.id)
    @player.connected!
    stale.connected!

    assert_equal 2, @player.reload.connections_count
  end
end
