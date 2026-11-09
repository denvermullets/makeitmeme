require 'test_helper'
require 'turbo/broadcastable/test_helper'

# Solid Cable does not order updates across streams, so what a phone ends up showing after a phase change
# must not depend on which stream's update arrives last: nothing may be replaced twice with different content.
class PhaseBroadcastTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @room = room_with_players
    seed_templates(30)
    @host = @room.player_for('ada')
  end

  def assert_no_competing_replacements(label)
    @room.players.each do |player|
      streams = capture_turbo_stream_broadcasts(@room) + capture_turbo_stream_broadcasts([@room, player])
      assert_not_empty streams, "#{label}: #{player.nickname} hears nothing"
      streams.group_by { |stream| stream['target'] }.each do |target, updates|
        assert_equal 1, updates.map(&:to_html).uniq.size,
                     "#{label}: #{target} is replaced with different content for #{player.nickname}"
      end
    end
  end

  def change_phase(label)
    ActionCable.server.pubsub.clear
    yield
    assert_no_competing_replacements(label)
  end

  test 'every phase change of a whole Game reaches a phone as one set of non-competing updates' do
    seen = []
    change_phase('start') { @room.start(by: @host) }
    submit_memes(@room, 'ada', 'bob', 'cy')
    40.times do
      break if @room.reload.waiting?

      change_phase(@room.phase) { @room.advance! }
      seen << @room.phase
      submit_memes(@room, 'ada', 'bob', 'cy') if @room.captioning?
      break if @room.scoreboard?
    end
    change_phase('play again') { @room.play_again(by: @host) }

    assert_includes seen, 'vote'
    assert_includes seen, 'reveal'
    assert_includes seen, 'standings'
    assert_includes seen, 'scoreboard'
  end
end
