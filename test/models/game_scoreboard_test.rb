require 'test_helper'

class GameScoreboardTest < ActiveSupport::TestCase
  setup do
    seed_templates(30)
    @room = room_with_players
    @room.start(by: @room.player_for('ada'))
    @game = @room.current_game
  end

  def seat(nickname) = @game.game_players.find_by!(nickname:)

  def meme(round, nickname, buddy_count)
    Meme.create!(round:, game_player: seat(nickname), buddy_count:)
  end

  def sql_during(&)
    sql = []
    callback = ->(*, payload) { sql << payload[:sql] unless payload[:name] == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &)
    sql
  end

  test 'rows carry place, nickname, total and Buddies received, ties sharing a place' do
    seat('Ada').update!(total: 5)
    seat('Bob').update!(total: 5)
    round1 = Round.create!(game: @game, number: 8)
    round2 = Round.create!(game: @game, number: 9)
    meme(round1, 'Ada', 2)
    meme(round2, 'Ada', 1)
    meme(round1, 'Cy', 4)

    rows = @game.scoreboard.rows

    assert_equal [[1, 'Ada', 5, 3], [1, 'Bob', 5, 0], [3, 'Cy', 0, 4]],
                 rows.map { |r| [r.place, r.nickname, r.total, r.buddies_received] }
  end

  test 'loads in a fixed number of queries and never reads Players or Templates' do
    sql = sql_during { @game.scoreboard.rows }
    assert_operator sql.length, :<=, 2
    assert(sql.none? { |q| q.match?(/FROM "(players|templates)"/) })

    5.times { |i| @game.game_players.create!(nickname: "Extra#{i}") }
    assert_equal sql.length, sql_during { @game.scoreboard.rows }.length
  end
end
