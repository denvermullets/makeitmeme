# One run of three Rounds within a Room. Keeps its own copies of everything its Recap shows (ADR 0002).
class Game < ApplicationRecord
  belongs_to :room
  has_many :game_players, dependent: :destroy
  has_many :rounds, dependent: :destroy

  has_secure_token :recap_token

  enum :status, { in_progress: 'in_progress', finished: 'finished' }, default: :in_progress

  Placing = Struct.new(:game_player, :place)
  RoundMemes = Struct.new(:round, :memes, :memes_of_the_round)

  # A Placing per game-player, highest total first. Place is 1 + the number with a strictly higher total,
  # so ties share a place (1, 1, 3). Reads cached totals only.
  # `preloaded: true` ranks the already-loaded seats in memory (the Admin list includes them), adding no query per Game.
  def placed_game_players(preloaded: false)
    ordered = if preloaded
                game_players.sort_by { |seat| [-seat.total, seat.id] }
              else
                game_players.order(total: :desc, id: :asc).to_a
              end
    ordered.map do |game_player|
      Placing.new(game_player, ordered.count { |other| other.total > game_player.total } + 1)
    end
  end

  # The Game's final Scoreboard read model (see Game::Scoreboard).
  def scoreboard = Game::Scoreboard.new(self)

  # RoundMemes (Round, its Memes, and the Memes of the Round among them) for Rounds that have Memes: Rounds in number order, Memes in voting position. Reads the Memes'
  # baked images and cached fields and the maker's nickname snapshot only, never Templates or Players. 3 queries.
  def memes_by_round
    memes = Meme.where(round: rounds).includes(:game_player, image_attachment: :blob).order(:position, :id)
    memes = memes.group_by(&:round_id)
    rounds.order(:number).filter_map do |round|
      next unless memes[round.id]

      RoundMemes.new(round, memes[round.id], Round.top_scoring(memes[round.id]))
    end
  end

  # The Player's seat in this Game, or nil.
  def game_player_for(player)
    game_players.find_by(player_id: player.id) if player
  end
end
