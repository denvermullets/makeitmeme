require 'test_helper'

class RoomActivityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @room = room_with_players
    seed_templates(30)
  end

  test 'touch_activity! records now' do
    travel_to(1.hour.from_now) do
      @room.touch_activity!

      assert_in_delta Time.current, @room.reload.last_activity_at, 1
    end
  end

  test 'joins, Host actions and transitions touch activity' do
    ada = @room.player_for('ada')
    travel_to(1.hour.from_now) do
      Room.join(code: @room.code, nickname: 'Dee', browser_token: 'dee')

      assert_in_delta Time.current, @room.reload.last_activity_at, 1
    end
    travel_to(2.hours.from_now) do
      @room.toggle_pack(pack: Pack.create!(name: 'P'), by: ada)

      assert_in_delta Time.current, @room.reload.last_activity_at, 1
    end
    travel_to(3.hours.from_now) do
      @room.start(by: ada)

      assert_in_delta Time.current, @room.reload.last_activity_at, 1
    end
    travel_to(4.hours.from_now) do
      @room.advance!

      assert_in_delta Time.current, @room.reload.last_activity_at, 1
    end
  end

  test 'play again touches activity' do
    ada = @room.player_for('ada')
    @room.start(by: ada)
    @room.update_columns(phase: 'scoreboard', phase_seq: 9)
    travel_to(1.hour.from_now) do
      @room.play_again(by: ada)

      assert_in_delta Time.current, @room.reload.last_activity_at, 1
    end
  end

  test 'presence-style changes on a Player are not activity' do
    before = @room.last_activity_at
    travel_to(1.hour.from_now) { @room.player_for('bob').touch }

    assert_equal before.to_i, @room.reload.last_activity_at.to_i
  end

  test 'expire_idle! expires only Rooms idle 2h, deleting Players and keeping the Room and Games' do
    idle = room_with_players
    idle.start(by: idle.player_for('ada'))
    active = room_with_players

    travel_to(2.hours.from_now + 1.minute) do
      active.touch_activity!

      assert_equal 2, Room.expire_idle! # idle + the setup Room
    end

    idle.reload
    assert idle.expired_at
    assert_equal 0, idle.players.count
    assert_nil idle.host_player_id
    assert_equal 1, idle.games.count
    assert_equal %w[Ada Bob Cy], idle.games.first.game_players.order(:id).map(&:nickname)
    assert(idle.games.first.game_players.all? { |gp| gp.player_id.nil? })
    assert_nil active.reload.expired_at
    assert_equal 3, active.players.count
  end

  test 'a Room just under 2h is kept' do
    travel_to(2.hours.from_now - 1.minute) { assert_equal 0, Room.expire_idle! }
  end

  test 'an expired Room accepts no joins and no transitions' do
    @room.start(by: @room.player_for('ada'))
    seq = @room.reload.phase_seq
    travel_to(3.hours.from_now) do
      Room.expire_idle!

      assert_raises(ActiveRecord::RecordInvalid) { Room.join(code: @room.code, nickname: 'Dee', browser_token: 'dee') }
      assert_not @room.reload.advance!
      PhaseDeadlineJob.perform_now(@room.id, seq)
      SweepOverdueRoomsJob.perform_now
    end

    assert_equal seq, @room.reload.phase_seq
  end
end
