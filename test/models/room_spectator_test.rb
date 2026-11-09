require 'test_helper'

# Spectators: Players who arrive mid-Game have no game-player row until the next Game.
class RoomSpectatorTest < ActiveSupport::TestCase
  setup do
    @room = room_with_players
    seed_templates(30)
    @ada = @room.player_for('ada')
    @room.start(by: @ada)
  end

  def join_late(nickname = 'Dee')
    Room.join(code: @room.code, nickname:, browser_token: "#{nickname.downcase}-token")
  end

  test 'joining during Captioning makes a Spectator with no seat or Hand' do
    dee = join_late

    assert @room.reload.spectator?(dee)
    assert_not @room.spectator?(@room.player_for('bob'))
    assert_nil @room.game_player_for(dee)
    assert_nil @room.hand_for(dee)
    assert_equal 3, @room.current_game.game_players.count
  end

  test 'joining in Waiting is not a Spectator' do
    room = room_with_players
    assert_not room.spectator?(Room.join(code: room.code, nickname: 'Dee', browser_token: 'dee'))
  end

  test 'a Spectator cannot submit a Meme or vote' do
    dee = join_late
    assert_raises(ActiveRecord::RecordInvalid) do
      @room.submit_meme(by: dee, signed_id: 'x', template_id: 1, captions: {})
    end

    submit_memes(@room, 'ada', 'bob')
    @room.advance!
    assert @room.reload.vote?
    error = assert_raises(ActiveRecord::RecordInvalid) do
      @room.cast_vote(by: dee, meme_id: @room.current_meme_id, kind: 'up')
    end
    assert_match(/not in this Game/, error.message)
  end

  test 'Spectators count towards the limit' do
    (Room::MAX_PLAYERS - 3).times { |i| join_late("Sp#{i}") }

    error = assert_raises(ActiveRecord::RecordInvalid) { join_late('Eleven') }
    assert_match(/Room is full/, error.message)
  end

  test 'the next Game deals Spectators in' do
    dee = join_late
    3.times { travel_to(@room.reload.phase_deadline_at + 1.second) { @room.advance! } }
    @room.play_again(by: @ada)
    assert @room.reload.waiting?

    @room.start(by: @ada)

    @room.reload
    assert_not @room.spectator?(dee)
    assert_not_nil @room.game_player_for(dee)
    assert_not_nil @room.hand_for(dee)
  end
end
