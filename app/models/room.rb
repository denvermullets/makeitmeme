class Room < ApplicationRecord
  CODE_LETTERS = ('A'..'Z').to_a.freeze
  CODE_LENGTH = 4
  CODE_ATTEMPTS = 10
  MAX_PLAYERS = 10
  MIN_PLAYERS = 3
  ROUNDS_PER_GAME = 3
  MIN_DEALABLE_TEMPLATES = 10
  START_GATE_REASON = "Turn on Packs with at least #{MIN_DEALABLE_TEMPLATES} Templates".freeze

  enum :phase, { waiting: 'waiting', captioning: 'captioning', vote: 'vote', reveal: 'reveal',
                 scoreboard: 'scoreboard' }, default: :waiting

  include Rejectable
  include PhaseEngine
  include Voting
  include Activity
  include Membership
  include Presence
  include HostHandoff
  include EarlyFinish
  include VoteEarlyClose

  after_update_commit :broadcast_packs!, if: :saved_change_to_off_pack_ids?

  has_many :players, dependent: :destroy
  has_many :games, dependent: :destroy
  belongs_to :current_game, class_name: 'Game', optional: true, inverse_of: false
  belongs_to :host, class_name: 'Player', foreign_key: :host_player_id, optional: true, inverse_of: false

  scope :live, -> { where(expired_at: nil) }
  # Live Rooms where the Pack list is on screen: Waiting and the Scoreboard.
  scope :showing_packs, -> { live.where(phase: %w[waiting scoreboard]) }
  # Live Rooms whose phase deadline has passed: what the crash sweep advances.
  scope :overdue, -> { live.where(phase_deadline_at: ..Time.current) }

  # Re-sends the Pack list (and Start gate) to every Room showing it. Called after Pack and Template changes commit.
  def self.broadcast_packs_to_open_rooms
    showing_packs.find_each(&:broadcast_packs!)
  end

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

  # The live Room with this code (any letter case), or nil.
  def self.live_by_code(code)
    live.find_by(code: code.to_s.upcase)
  end

  # An expired Room that once held this code (any letter case), or nil. Only meaningful when no live Room has it.
  def self.expired_by_code(code)
    where.not(expired_at: nil).find_by(code: code.to_s.upcase)
  end

  def self.missing_room_message(code)
    expired_by_code(code) ? 'This Room has ended' : 'No live Room with that code'
  end
  private_class_method :missing_room_message

  # Room game operation: join a live Room by code. A browser that already has a Player in the
  # Room gets that Player back; a nickname held by an Away Player takes that Player over.
  # Raises ActiveRecord::RecordInvalid with a clear message otherwise.
  def self.join(code:, nickname:, browser_token:)
    room = live_by_code(code) || new.reject!(missing_room_message(code))

    room.with_lock do
      room.player_for(browser_token) || begin
        room.take_over_away_player(nickname:, browser_token:) || room.add_player(nickname:, browser_token:)
      end
    end
  end

  # Room game operation: the Host starts a Game. Everyone in the Room is dealt in and Round 1 begins.
  # Raises ActiveRecord::RecordInvalid unless the caller is the Host, the Room is waiting, there are
  # enough Players and the Room has enough dealable Templates (the Start gate).
  def start(by:)
    with_lock do
      reject!('Only the Host can start the Game') unless host?(by)
      reject!('A Game is already under way') unless waiting?
      reject!(present_players_gate_reason) if present_players_gate_reason
      reject!(START_GATE_REASON) unless enough_dealable_templates?

      game = games.create!
      players.each { |player| game.game_players.create!(player:, nickname: player.nickname) }
      enter_captioning!(game:, number: 1)
      touch_activity!
    end
    self
  end

  # The Start gate: the Room needs at least MIN_DEALABLE_TEMPLATES dealable Templates.
  def enough_dealable_templates?
    Template.dealable_for(self).count >= MIN_DEALABLE_TEMPLATES
  end

  # Room game operation: the Host turns a Pack on or off for the next Game (`on:` nil flips it).
  # Raises ActiveRecord::RecordInvalid unless the caller is the Host and the Room is in Waiting or on the Scoreboard.
  def toggle_pack(pack:, by:, on: nil)
    with_lock do
      reject!('Only the Host can choose Packs') unless host?(by)
      reject!('Packs can only be changed between Games') unless waiting? || scoreboard?

      on = pack_off?(pack) if on.nil?
      update!(off_pack_ids: on ? off_pack_ids - [pack.id] : (off_pack_ids | [pack.id]))
      touch_activity!
    end
    self
  end

  def pack_off?(pack) = off_pack_ids.include?(pack.id)

  # Room game operation: the Host sends the Room from the Scoreboard back to Waiting.
  # Raises ActiveRecord::RecordInvalid unless the caller is the Host and the Room is on the Scoreboard.
  def play_again(by:)
    with_lock do
      reject!('Only the Host can play again') unless host?(by)
      reject!('The Game is not over yet') unless scoreboard?
      reject!(present_players_gate_reason) if present_players_gate_reason

      advance!(from_seq: phase_seq)
      touch_activity!
    end
    self
  end

  # Room game operation: a Player submits their baked Meme for the current Round. `signed_id` is the
  # direct-uploaded PNG's blob, `captions` the texts by Text Box. Returns the Meme; raises
  # ActiveRecord::RecordInvalid (wrong phase, too late, not in the Hand, already submitted, bad file).
  def submit_meme(by:, signed_id:, template_id:, captions:)
    with_lock do
      reject!('Memes can only be submitted during Captioning') unless captioning?
      reject!('Time is up') if closed?

      hand = hand_for(by) || reject!('You are not in this Game')
      Meme.submit(hand:, template_id:, signed_id:, captions:).tap { finish_early_if_done! }
    end
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

  # A Player with no seat in the Game under way: arrived mid-Game, dealt in on the next Game.
  def spectator?(player)
    !waiting? && current_game.present? && game_player_for(player).nil?
  end

  def host?(player)
    player.present? && player.id == host_player_id
  end

  def player_for(browser_token)
    return if browser_token.blank?

    players.find_by(browser_token:)
  end

  # Call after commit: every Player gets their own Pack list (and, in Waiting, Start gate), one stream each, so
  # Host-only buttons never reach other Players.
  def broadcast_packs!
    players.each do |player|
      broadcast_replace_to self, player, target: 'pack_list', partial: 'rooms/pack_list',
                                         locals: { room: self, player: }
      next unless waiting?

      broadcast_replace_to self, player, target: 'start_gate', partial: 'rooms/start_gate',
                                         locals: { room: self, player: }
    end
  end
end
