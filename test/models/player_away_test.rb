require 'test_helper'
require 'turbo/broadcastable/test_helper'

module AwayRecorder
  mattr_accessor :calls

  def player_went_away!(player)
    calls&.push(player.id)
    super
  end
end
Room.prepend(AwayRecorder)

class PlayerAwayTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @room = room_with_players
    @bob = @room.player_for('bob')
    @bob.connected!
    clear_enqueued_jobs
    ActionCable.server.pubsub.clear
  end

  test 'the last connection closing schedules the grace job with the presence token' do
    token = @bob.reload.presence_token

    assert_enqueued_with(job: PresenceGraceJob, args: [@bob.id, token], at: Player::AWAY_GRACE.from_now) do
      @bob.disconnected!
    end
  end

  test 'the grace job is enqueued only once the surrounding transaction commits' do
    Player.transaction do
      @bob.disconnected!
      assert_no_enqueued_jobs(only: PresenceGraceJob)
    end
    assert_enqueued_jobs 1, only: PresenceGraceJob
  end

  test 'closing one of several tabs schedules nothing' do
    @bob.connected!
    assert_no_enqueued_jobs(only: PresenceGraceJob) { @bob.disconnected! }
  end

  test 'the grace job marks the Player Away and runs the away consequences once' do
    @bob.disconnected!
    AwayRecorder.calls = []
    perform_enqueued_jobs(only: PresenceGraceJob)

    assert @bob.reload.away?
    assert_not @bob.here?
    assert_equal [@bob.id], AwayRecorder.calls
    assert_equal [@room.player_for('ada').id, @room.player_for('cy').id].sort,
                 @room.players.here.pluck(:id).sort
  end

  test 'a stale job (the Player reconnected during the grace) does nothing' do
    @bob.disconnected!
    @bob.connected!
    @bob.disconnected!
    stale_token = @bob.reload.presence_token - 1

    PresenceGraceJob.perform_now(@bob.id, stale_token)

    assert @bob.reload.here?
  end

  test 'a job whose Player still has a connection does nothing' do
    token = @bob.reload.presence_token
    @bob.connected!
    PresenceGraceJob.perform_now(@bob.id, token)

    assert @bob.reload.here?
  end

  test 'a job for a deleted Player does nothing' do
    token = @bob.reload.presence_token
    @bob.destroy!

    assert_nothing_raised { PresenceGraceJob.perform_now(@bob.id, token) }
  end

  test 'reconnecting clears Away straight away' do
    @bob.disconnected!
    PresenceGraceJob.perform_now(@bob.id, @bob.reload.presence_token)
    assert @bob.reload.away?

    @bob.connected!

    assert @bob.reload.here?
    assert_nil @bob.away_at
  end

  test 'going Away and coming back are each broadcast once on the Room stream' do
    @bob.disconnected!
    ActionCable.server.pubsub.clear

    assert_turbo_stream_broadcasts @room, count: 1 do
      PresenceGraceJob.perform_now(@bob.id, @bob.reload.presence_token)
    end
    assert_turbo_stream_broadcasts @room, count: 1 do
      @bob.connected!
    end
  end

  test 'a plain connect of a present Player broadcasts nothing' do
    assert_no_turbo_stream_broadcasts(@room) { @bob.connected! }
  end

  test 'presence changes do not touch Room activity' do
    @room.update_column(:last_activity_at, 1.hour.ago)
    stamp = @room.reload.last_activity_at
    @bob.disconnected!
    PresenceGraceJob.perform_now(@bob.id, @bob.reload.presence_token)
    @bob.connected!

    assert_equal stamp, @room.reload.last_activity_at
  end

  test 'the grace is 20 seconds' do
    assert_equal 20.seconds, Player::AWAY_GRACE
  end

  test 'the Away marker renders in the Player list' do
    @bob.update!(away_at: Time.current)
    html = ApplicationController.render(partial: 'players/player', locals: { player: @bob })

    assert_includes html, 'Away'
  end
end
