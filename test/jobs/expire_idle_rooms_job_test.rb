require 'test_helper'

class ExpireIdleRoomsJobTest < ActiveSupport::TestCase
  test 'expires idle Rooms' do
    room = room_with_players

    travel_to(2.hours.from_now + 1.minute) { ExpireIdleRoomsJob.perform_now }

    assert room.reload.expired_at
  end

  test 'is scheduled' do
    config = YAML.load_file(Rails.root.join('config/recurring.yml'), aliases: true)

    assert(config.values.flat_map(&:values).any? { |t| t['class'] == 'ExpireIdleRoomsJob' })
  end
end
