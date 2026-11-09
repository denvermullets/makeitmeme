# Expires Rooms idle for Room::Activity::IDLE_LIMIT (2 hours).
class ExpireIdleRoomsJob < ApplicationJob
  def perform
    Room.expire_idle!
  end
end
