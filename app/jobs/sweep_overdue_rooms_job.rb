# Crash backstop (ADR 0001): advances every live Room whose deadline has passed, even if its
# PhaseDeadlineJob was lost. Uses the same phase_seq-guarded path, so it can never double-advance.
class SweepOverdueRoomsJob < ApplicationJob
  def perform
    Room.overdue.find_each do |room|
      room.advance!(from_seq: room.phase_seq, only_if_due: true)
    end
  end
end
