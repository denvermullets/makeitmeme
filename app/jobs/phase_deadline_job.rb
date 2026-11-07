# Closes a timed phase at (or just after) its deadline. Carries the phase_seq it was scheduled for, so a
# job whose phase already ended early finds a different phase_seq and does nothing (ADR 0001).
class PhaseDeadlineJob < ApplicationJob
  retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: 1.second, attempts: 5

  def perform(room_id, phase_seq)
    Room.find_by(id: room_id)&.advance!(from_seq: phase_seq, only_if_due: true)
  end
end
