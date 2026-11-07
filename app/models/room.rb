class Room < ApplicationRecord
  CODE_LETTERS = ('A'..'Z').to_a.freeze
  CODE_LENGTH = 4
  CODE_ATTEMPTS = 10
  MAX_PLAYERS = 10
  MIN_PLAYERS = 3
  ROUNDS_PER_GAME = 3

  # Seconds each timed phase lasts. One place to change them; tests shorten them.
  class_attribute :phase_seconds, default: { captioning: 90, vote: 15, reveal: 4 }

  enum :phase, { waiting: 'waiting', captioning: 'captioning', scoreboard: 'scoreboard' }, default: :waiting

  has_many :players, dependent: :destroy
  has_many :games, dependent: :destroy
  belongs_to :current_game, class_name: 'Game', optional: true, inverse_of: false
  belongs_to :host, class_name: 'Player', foreign_key: :host_player_id, optional: true, inverse_of: false

  scope :live, -> { where(expired_at: nil) }

  # Every phase change reaches phones only after commit, and before any content for that phase.
  after_update_commit :phase_changed, if: :saved_change_to_phase_seq?

  # Room game operation: create a Room and its Host Player.
  # Raises ActiveRecord::RecordInvalid when the nickname is not acceptable.
  def self.create_with_host(nickname:, browser_token:, codes: nil)
    transaction do
      room = insert_with_unique_code(codes || random_codes)
      host = room.players.create!(nickname:, browser_token:, joined_at: Time.current)
      room.update!(host:)
      room
    end
  end

  # Room game operation: join a live Room by code. A browser that already has a Player in the
  # Room gets that Player back. Raises ActiveRecord::RecordInvalid with a clear message otherwise.
  def self.join(code:, nickname:, browser_token:)
    room = live.find_by(code: code.to_s.upcase)
    raise_rejected('No live Room with that code') unless room

    room.with_lock do
      room.player_for(browser_token) || begin
        raise_rejected("Room is full (#{MAX_PLAYERS} Players)") if room.players.count >= MAX_PLAYERS

        room.players.create!(nickname:, browser_token:, joined_at: Time.current)
      end
    end
  end

  def self.raise_rejected(message)
    new.reject!(message)
  end
  private_class_method :raise_rejected

  # Raises RecordInvalid carrying `message` as a base error.
  def reject!(message)
    errors.add(:base, message)
    raise ActiveRecord::RecordInvalid, self
  end

  # Room game operation: the Host starts a Game. Everyone in the Room is dealt in and Round 1 begins.
  # Raises ActiveRecord::RecordInvalid unless the caller is the Host, the Room is waiting, there are
  # enough Players and the Template Library can fill a Hand.
  def start(by:)
    with_lock do
      reject!('Only the Host can start the Game') unless host?(by)
      reject!('A Game is already under way') unless waiting?
      reject!("Need at least #{MIN_PLAYERS} Players to start") if players.count < MIN_PLAYERS
      reject!("Need at least #{Hand::SIZE} Templates in the Library to start") if Template.count < Hand::SIZE

      game = games.create!
      players.each { |player| game.game_players.create!(player:, nickname: player.nickname) }
      enter_captioning!(game:, number: 1)
    end
    self
  end

  # The one way a Room changes phase. Locks the Room row, then moves to the next phase and runs its entry work.
  # Returns false (and does nothing) when the Room is no longer in the phase the caller meant:
  # `from_seq` is the phase_seq the caller saw, `only_if_due` also requires the deadline to have passed
  # (deadline job and crash sweep). Early finishes call it plain. The deadline job and the broadcast
  # follow the commit (see `phase_changed`). New phases add a `when` branch here and an `enter_*!` step.
  def advance!(from_seq: nil, only_if_due: false)
    with_lock do
      next false if from_seq && phase_seq != from_seq
      next false if only_if_due && (phase_deadline_at.nil? || phase_deadline_at > Time.current)

      case phase
      when 'captioning' then finish_captioning!
      else next false
      end
      true
    end
  end

  # Entry step: deal this Round's Hands and start its Captioning. Call under the Room row lock.
  def enter_captioning!(game:, number:)
    game.rounds.create!(number:).deal_hands!
    enter_phase!(:captioning, current_game: game, current_round_number: number)
  end

  # Entry step: the Game is over. No deadline.
  def enter_scoreboard!
    current_game.update!(status: :finished, finished_at: Time.current)
    enter_phase!(:scoreboard)
  end

  # The Player's own Hand for the current Round, or nil (not dealt in, or no Round under way).
  def hand_for(player)
    return unless current_game && current_round_number

    Hand.joins(:round, :game_player).find_by(rounds: { game_id: current_game_id, number: current_round_number },
                                             game_players: { player_id: player.id })
  end

  # An endless stream of candidate codes. Tests pass their own `codes:` to force a clash.
  def self.random_codes
    Enumerator.produce { Array.new(CODE_LENGTH) { CODE_LETTERS.sample }.join }
  end

  # A clash on the partial unique index is retried with a fresh code. The savepoint
  # keeps the outer transaction usable after the failed insert.
  def self.insert_with_unique_code(codes)
    attempts = 0
    begin
      transaction(requires_new: true) { create!(code: codes.next, last_activity_at: Time.current) }
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      raise if attempts >= CODE_ATTEMPTS

      retry
    end
  end
  private_class_method :insert_with_unique_code

  def host?(player)
    player.present? && player.id == host_player_id
  end

  def player_for(browser_token)
    return if browser_token.blank?

    players.find_by(browser_token:)
  end

  private

  # Every entry step ends here: new phase, bumped phase_seq, and the deadline when the phase has a duration.
  def enter_phase!(phase, **attrs)
    seconds = self.class.phase_seconds[phase.to_sym]
    update!(phase:, phase_seq: phase_seq + 1, phase_deadline_at: seconds&.seconds&.from_now,
            last_activity_at: Time.current, **attrs)
  end

  # With no Memes yet, Captioning moves straight on: the next Round, or the Scoreboard after the last.
  def finish_captioning!
    if current_round_number < ROUNDS_PER_GAME
      enter_captioning!(game: current_game, number: current_round_number + 1)
    else
      enter_scoreboard!
    end
  end

  # After commit: schedule the phase's deadline job, then tell the phones.
  def phase_changed
    PhaseDeadlineJob.set(wait_until: phase_deadline_at).perform_later(id, phase_seq) if phase_deadline_at
    broadcast_phase
  end

  def broadcast_phase
    broadcast_replace_to self, target: 'screen', partial: 'rooms/screen', locals: { room: self, player: nil }
    players.each do |player|
      broadcast_replace_to self, player, target: 'hand', partial: 'hands/hand',
                                         locals: { hand: hand_for(player), room: self }
    end
  end
end
