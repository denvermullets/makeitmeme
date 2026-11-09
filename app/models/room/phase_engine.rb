# The Room's phase engine: the one locked entry point (`advance!`), the entry step of each phase and the
# after-commit deadline job and broadcast. Voting phases (vote, reveal) live in Room::Voting.
module Room::PhaseEngine
  extend ActiveSupport::Concern

  # At the Captioning deadline the phones bake and upload the Meme on screen, so the server extends the deadline
  # once by this much (same phase, later deadline, new deadline job) instead of advancing. See `extend_deadline!`.
  UPLOAD_GRACE = 5.seconds
  # Likewise a Vote tapped at the last moment.
  VOTE_GRACE = 1.second

  # Per phase: `next_step` runs when the phase ends (its entry work for what comes next), `grace` is how long
  # past the deadline it still takes input, and `screen` says who is sent the phase's screen. Solid Cable does
  # not order updates across streams, so a phase is sent either on the shared Room stream (`:shared`, nothing
  # Player-specific on it) or on each Player's own stream (`:per_player`), never both.
  PHASES = {
    waiting: { next_step: nil, grace: 0.seconds, screen: :per_player },
    captioning: { next_step: :finish_captioning!, grace: 0.seconds, screen: :per_player },
    vote: { next_step: :enter_reveal!, grace: VOTE_GRACE, screen: :per_player },
    reveal: { next_step: :finish_reveal!, grace: 0.seconds, screen: :shared },
    scoreboard: { next_step: :enter_waiting!, grace: 0.seconds, screen: :per_player }
  }.freeze

  included do
    # Seconds each timed phase lasts. One place to change them; tests shorten them.
    # Captioning is absent: its length is the Room's preset (`captioning_seconds`). Tests may set `captioning:` to
    # override it.
    class_attribute :phase_seconds, default: { vote: 15, reveal: 4 }

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
      next extend_deadline! if only_if_due && grace_due?

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

  # Past the point where the phase takes input: its deadline plus its grace. Captioning, until its deadline has been
  # extended, still takes a Meme for the upload grace (the deadline job may not have run yet).
  def closed?
    return false unless due_at

    Time.current > (captioning? && !upload_grace_used? ? due_at + UPLOAD_GRACE : due_at)
  end

  # The deadline the phones count down to: the Captioning deadline without its upload grace.
  def countdown_deadline_at
    upload_grace_used? ? phase_deadline_at - UPLOAD_GRACE : phase_deadline_at
  end

  private

  def phase_config = PHASES.fetch(phase.to_sym)

  # The caller's phase_seq still matches, and when it asked for a due-only advance, the deadline has passed.
  def advance_wanted?(from_seq, only_if_due)
    return false if from_seq && phase_seq != from_seq

    !only_if_due || (due_at.present? && due_at <= Time.current)
  end

  # Captioning's deadline has passed and its one upload grace has not been given yet.
  def grace_due? = captioning? && !upload_grace_used?

  # Gives Captioning its upload grace: the same phase with a later deadline. phase_seq is bumped so the new deadline
  # job is the only live one; the phones are not re-sent the screen (see `phase_changed`).
  def extend_deadline!
    update!(phase_seq: phase_seq + 1, phase_deadline_at: phase_deadline_at + UPLOAD_GRACE, upload_grace_used: true)
  end

  # When the phase may be closed: its deadline plus its grace.
  def due_at = phase_deadline_at&.then { |at| at + phase_config[:grace] }

  # How long Captioning lasts: the test override in phase_seconds, else the Room's preset.
  def captioning_seconds = self.class.phase_seconds[:captioning] || preset_seconds

  # Every entry step ends here: new phase, bumped phase_seq, and the deadline when the phase has a duration.
  def enter_phase!(phase, **attrs)
    seconds = phase.to_sym == :captioning ? captioning_seconds : self.class.phase_seconds[phase.to_sym]
    update!(phase:, phase_seq: phase_seq + 1, phase_deadline_at: seconds&.seconds&.from_now, upload_grace_used: false,
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
    broadcast_phase unless grace_extension?
  end

  # The upload grace changes no screen: a phone mid-upload must not have its editor replaced.
  def grace_extension? = saved_change_to_upload_grace_used? && upload_grace_used?

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
