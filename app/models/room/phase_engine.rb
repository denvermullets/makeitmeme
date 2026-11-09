# The Room's phase engine: the one locked entry point (`advance!`), the entry step of each phase and the
# after-commit deadline job and broadcast. Voting phases (vote, reveal) live in Room::Voting.
module Room::PhaseEngine
  extend ActiveSupport::Concern

  # Captioning stays open this long past its deadline, so a Meme auto-submitted at the client's zero still lands.
  UPLOAD_GRACE = 1.second
  # Likewise a Vote tapped at the last moment.
  VOTE_GRACE = 1.second

  # Per phase: `next_step` runs when the phase ends (its entry work for what comes next), `grace` is how long
  # past the deadline it still takes input, and `screen` says who is sent the phase's screen. Solid Cable does
  # not order updates across streams, so a phase is sent either on the shared Room stream (`:shared`, nothing
  # Player-specific on it) or on each Player's own stream (`:per_player`), never both.
  PHASES = {
    waiting: { next_step: nil, grace: 0.seconds, screen: :per_player },
    captioning: { next_step: :finish_captioning!, grace: UPLOAD_GRACE, screen: :per_player },
    vote: { next_step: :enter_reveal!, grace: VOTE_GRACE, screen: :per_player },
    reveal: { next_step: :finish_reveal!, grace: 0.seconds, screen: :shared },
    scoreboard: { next_step: :enter_waiting!, grace: 0.seconds, screen: :per_player }
  }.freeze

  included do
    # Seconds each timed phase lasts. One place to change them; tests shorten them.
    class_attribute :phase_seconds, default: { captioning: 90, vote: 15, reveal: 4 }

    # Every phase change reaches phones only after commit, and before any content for that phase.
    after_update_commit :phase_changed, if: :saved_change_to_phase_seq?
  end

  # The one way a Room changes phase. Locks the Room row, then moves to the next phase and runs its entry work.
  # Returns false (and does nothing) when the Room is no longer in the phase the caller meant:
  # `from_seq` is the phase_seq the caller saw, `only_if_due` also requires the deadline to have passed
  # (deadline job and crash sweep). Early finishes call it plain. The deadline job and the broadcast
  # follow the commit (see `phase_changed`). New phases add a PHASES entry and an `enter_*!` step.
  def advance!(from_seq: nil, only_if_due: false)
    with_lock do
      next false if expired?
      next false unless advance_wanted?(from_seq, only_if_due)

      step = phase_config[:next_step]
      next false unless step

      send(step)
      true
    end
  end

  # Entry step: deal this Round's Hands and start its Captioning. Call under the Room row lock.
  def enter_captioning!(game:, number:)
    game.rounds.create!(number:).deal_hands!
    enter_phase!(:captioning, current_game: game, current_round_number: number, current_meme: nil)
  end

  # Entry step: the Game is over. No deadline.
  def enter_scoreboard!
    current_game.update!(status: :finished, finished_at: Time.current)
    enter_phase!(:scoreboard, current_meme: nil)
  end

  # Entry step: back to Waiting with the same code and Players. The finished Game stays as it was;
  # the Room just stops pointing at it. No deadline.
  def enter_waiting!
    enter_phase!(:waiting, current_game: nil, current_round_number: nil, current_meme: nil)
  end

  # Past the point where the phase takes input: its deadline plus its grace.
  def closed? = due_at.present? && Time.current > due_at

  private

  def phase_config = PHASES.fetch(phase.to_sym)

  # The caller's phase_seq still matches, and when it asked for a due-only advance, the deadline has passed.
  def advance_wanted?(from_seq, only_if_due)
    return false if from_seq && phase_seq != from_seq

    !only_if_due || (due_at.present? && due_at <= Time.current)
  end

  # When the phase may be closed: its deadline plus its grace.
  def due_at = phase_deadline_at&.then { |at| at + phase_config[:grace] }

  # Every entry step ends here: new phase, bumped phase_seq, and the deadline when the phase has a duration.
  def enter_phase!(phase, **attrs)
    seconds = self.class.phase_seconds[phase.to_sym]
    update!(phase:, phase_seq: phase_seq + 1, phase_deadline_at: seconds&.seconds&.from_now,
            last_activity_at: Time.current, **attrs)
  end

  # The next Round, or the Scoreboard after the last.
  def enter_next_round_or_scoreboard!
    if current_round_number < Room::ROUNDS_PER_GAME
      enter_captioning!(game: current_game, number: current_round_number + 1)
    else
      enter_scoreboard!
    end
  end

  # After commit: schedule the phase's deadline job, then tell the phones.
  def phase_changed
    PhaseDeadlineJob.set(wait_until: due_at).perform_later(id, phase_seq) if phase_deadline_at
    broadcast_phase
  end

  # The phase's screen goes out once per viewer, on one stream each, so what a phone shows never depends on
  # which stream's update arrives last. Per-Player screens carry the Player's own content (Hand, Host buttons,
  # vote buttons).
  def broadcast_phase
    if phase_config[:screen] == :shared
      broadcast_replace_to self, target: 'screen', partial: 'rooms/screen', locals: { room: self, player: nil }
    else
      players.each do |player|
        broadcast_replace_to self, player, target: 'screen', partial: 'rooms/screen', locals: { room: self, player: }
      end
    end
  end
end
