require 'test_helper'

class AdminGamesTest < ActionDispatch::IntegrationTest
  setup { @room = Room.create_with_host(nickname: 'Ada', browser_token: 'ada') }

  # A Game with a seat per [nickname, total] and one Meme per seat in a single Round.
  def make_game(seats, finished_at: Time.current, status: :finished)
    game = Game.create!(room: @room, status: status, finished_at: finished_at)
    round = game.rounds.create!(number: 1)
    seats.each do |nickname, total|
      seat = game.game_players.create!(nickname: nickname, total: total)
      Meme.create!(round: round, game_player: seat)
    end
    game
  end

  def count_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end

  test 'the Games list is unreachable when signed out' do
    get admin_games_path
    assert_redirected_to admin_sign_in_path
  end

  test 'the admin layout links to the Games list' do
    sign_in_as_admin

    get admin_root_path

    assert_select 'header a[href=?]', admin_games_path
  end

  test 'lists only finished Games, newest finished first' do
    older = make_game([['Ada', 5]], finished_at: 2.days.ago)
    newer = make_game([['Bob', 5]], finished_at: 1.hour.ago)
    make_game([['Cy', 5]], status: :in_progress, finished_at: nil)
    sign_in_as_admin

    get admin_games_path

    assert_response :success
    assert_select '[data-game]', 2
    assert_select '[data-game]:nth-child(1)[data-game=?]', newer.id.to_s
    assert_select '[data-game]:nth-child(2)[data-game=?]', older.id.to_s
  end

  test 'each row shows the finished time, nicknames, Meme count, winners and a Recap link' do
    game = make_game([['Ada', 9], ['Bob', 9], ['Cy', 2]], finished_at: Time.utc(2026, 11, 9, 18, 30))
    sign_in_as_admin

    get admin_games_path

    assert_select "[data-game='#{game.id}']" do
      assert_select '.game-finished-at', /2026/
      assert_select '.game-nicknames', /Ada.*Bob.*Cy/m
      assert_select '.game-meme-count', '3'
      assert_select '.game-winners', /Ada.*Bob/m
      assert_select '.game-winners', text: /Cy/, count: 0
      assert_select 'a[href=?]', recap_path(game.recap_token)
    end
  end

  test 'is view-only and issues a fixed number of queries however many Games there are' do
    sign_in_as_admin
    make_game([['Ada', 1], ['Bob', 2]])
    get admin_games_path
    baseline = count_queries { get admin_games_path }

    4.times { make_game([['Ada', 1], ['Bob', 2], ['Cy', 3]]) }
    many = count_queries { get admin_games_path }

    assert_operator many, :<=, baseline
    assert_select 'main form', 0
    assert_select 'main button, main input[type=submit]', 0
  end
end
