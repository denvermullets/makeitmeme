require 'test_helper'

# Room game operation: the Host starts a Game and every Player is dealt a Hand.
class RoomStartTest < ActiveSupport::TestCase
  setup do
    @room = room_with_players
    @host = @room.player_for('ada')
    seed_templates
  end

  test 'starting moves the Room to Captioning of Round 1 with a 90s deadline' do
    freeze_time do
      @room.start(by: @host)

      assert @room.reload.captioning?
      assert_equal 1, @room.current_round_number
      assert_equal 90.seconds.from_now, @room.phase_deadline_at
      assert_equal 1, @room.phase_seq
    end
  end

  test 'every Player is dealt in with a nickname snapshot' do
    @room.start(by: @host)

    game_players = @room.reload.current_game.game_players
    assert_equal %w[Ada Bob Cy], game_players.map(&:nickname).sort
    assert_equal @room.players.sort_by(&:id), game_players.map(&:player).sort_by(&:id)
    assert(game_players.all? { |gp| gp.total.zero? })
    assert @room.current_game.recap_token.present?
  end

  test 'each Player holds a Hand of 10 distinct existing Templates' do
    seed_templates(5)
    @room.start(by: @host)

    @room.players.each do |player|
      hand = @room.hand_for(player)
      assert_equal 10, hand.template_ids.size
      assert_equal 10, hand.template_ids.uniq.size
      assert_empty hand.template_ids - Template.pluck(:id)
    end
  end

  test 'Hands are dealt at random, so Players may differ' do
    seed_templates(40)
    @room.start(by: @host)

    hands = @room.players.map { |player| @room.hand_for(player).template_ids }
    assert_operator hands.uniq.size, :>, 1
  end

  test 'only the Host can start' do
    bob = @room.player_for('bob')

    error = assert_raises(ActiveRecord::RecordInvalid) { @room.start(by: bob) }
    assert_match(/Host/, error.message)
    assert @room.reload.waiting?
  end

  test 'a Player of another Room cannot start this one' do
    other = Room.create_with_host(nickname: 'Zed', browser_token: 'zed')

    assert_raises(ActiveRecord::RecordInvalid) { @room.start(by: other.host) }
  end

  test 'a Game cannot be started twice' do
    @room.start(by: @host)

    assert_raises(ActiveRecord::RecordInvalid) { @room.start(by: @host) }
    assert_equal 1, @room.reload.phase_seq
    assert_equal 1, @room.games.count
  end

  test 'needs 3 or more Players' do
    room = Room.create_with_host(nickname: 'Dee', browser_token: 'dee')
    Room.join(code: room.code, nickname: 'Eve', browser_token: 'eve')

    assert_raises(ActiveRecord::RecordInvalid) { room.start(by: room.host) }
    assert room.reload.waiting?
  end

  test 'needs at least 10 Templates, and a refusal leaves nothing behind' do
    Template.last.destroy

    assert_raises(ActiveRecord::RecordInvalid) { @room.start(by: @host) }
    assert @room.reload.waiting?
    assert_equal 0, Game.count
  end
end
