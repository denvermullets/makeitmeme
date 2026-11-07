# A game operation refuses with a reason: RecordInvalid carrying the message as a base error.
module Rejectable
  def reject!(message)
    errors.add(:base, message)
    raise ActiveRecord::RecordInvalid, self
  end
end
