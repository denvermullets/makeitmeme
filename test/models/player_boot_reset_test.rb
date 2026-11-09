require 'test_helper'

class PlayerBootResetTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @room = room_with_players
    @ada = @room.player_for('ada')
    @bob = @room.player_for('bob')
    @cy = @room.player_for('cy')
    [@ada, @bob, @cy].each(&:connected!)
    @cy.update!(connections_count: 0, away_at: 1.minute.ago)
    clear_enqueued_jobs
  end

  test 'resets every connection count to 0' do
    Player.reset_presence!

    assert_equal([0, 0, 0], [@ada, @bob, @cy].map { |p| p.reload.connections_count })
  end

  test 'schedules a grace job with a bumped token for each Player who was not Away' do
    old_tokens = [@ada, @bob].to_h { |p| [p.id, p.reload.presence_token] }

    Player.reset_presence!

    [@ada, @bob].each do |p|
      token = p.reload.presence_token
      assert_equal old_tokens[p.id] + 1, token
      assert_enqueued_with(job: PresenceGraceJob, args: [p.id, token], at: Player::AWAY_GRACE.from_now)
    end
  end

  test 'Players already Away stay Away with no extra job' do
    before = @cy.reload.presence_token

    Player.reset_presence!

    assert_equal(2, enqueued_jobs.count { |j| j['job_class'] == 'PresenceGraceJob' })
    assert @cy.reload.away?
    assert_equal before, @cy.presence_token
  end

  test 'a Player who reconnects within the grace never becomes Away, one who does not does' do
    Player.reset_presence!
    @bob.reload.connected!

    travel_to(Player::AWAY_GRACE.from_now + 1) { perform_enqueued_jobs(only: PresenceGraceJob) }

    assert @bob.reload.present?
    assert @ada.reload.away?
  end
end
