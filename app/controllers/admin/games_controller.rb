module Admin
  # View-only list of finished Games, newest finished first. Reads the snapshot only (ADR 0002).
  class GamesController < BaseController
    PER_PAGE = 20

    def index
      @page = [params[:page].to_i, 1].max
      finished = Game.finished.includes(:game_players).order(finished_at: :desc, id: :desc)
      # One extra row tells us whether a next page exists without a COUNT.
      fetched = finished.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      @next_page = @page + 1 if fetched.size > PER_PAGE
      @games = fetched.first(PER_PAGE)
      @meme_counts = Meme.joins(:round).where(rounds: { game_id: @games.map(&:id) }).group('rounds.game_id').count
    end
  end
end
