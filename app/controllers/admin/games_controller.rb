module Admin
  # View-only list of finished Games, newest finished first. Reads the snapshot only (ADR 0002).
  class GamesController < BaseController
    def index
      @games = Game.finished.includes(:game_players).order(finished_at: :desc, id: :desc)
      @meme_counts = Meme.joins(:round).where(rounds: { game_id: @games.map(&:id) }).group('rounds.game_id').count
    end
  end
end
