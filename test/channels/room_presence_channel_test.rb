require 'test_helper'

class RoomPresenceChannelTest < ActionCable::Channel::TestCase
  setup do
    @room = room_with_players
  end

  test 'subscribing marks the Player as connected' do
    stub_connection(browser_token: 'bob')

    subscribe(code: @room.code)

    assert subscription.confirmed?
    assert_equal 1, @room.player_for('bob').connections_count
    assert_equal 0, @room.player_for('ada').connections_count
  end

  test 'unsubscribing marks the Player as disconnected' do
    stub_connection(browser_token: 'bob')
    subscribe(code: @room.code)

    unsubscribe

    assert_equal 0, @room.player_for('bob').connections_count
  end

  test 'several connections count as one presence until the last one closes' do
    stub_connection(browser_token: 'bob')
    subscribe(code: @room.code)
    first = subscription
    subscribe(code: @room.code)

    assert_equal 2, @room.player_for('bob').connections_count

    unsubscribe
    assert_equal 1, @room.player_for('bob').connections_count

    first.unsubscribe_from_channel
    assert_equal 0, @room.player_for('bob').connections_count
  end

  test 'rejects a browser that holds no Player in the Room' do
    stub_connection(browser_token: 'stranger')

    subscribe(code: @room.code)

    assert subscription.rejected?
  end

  test 'rejects an unknown Room code' do
    stub_connection(browser_token: 'bob')

    subscribe(code: 'NOPE')

    assert subscription.rejected?
  end

  test 'a Player with no game row, like a Spectator, still subscribes' do
    spectator = Room.join(code: @room.code, nickname: 'Dee', browser_token: 'dee')
    stub_connection(browser_token: 'dee')

    subscribe(code: @room.code)

    assert subscription.confirmed?
    assert_equal 1, spectator.reload.connections_count
  end
end
