require 'test_helper'

class StandingsScreenTest < ActionDispatch::IntegrationTest
  setup do
    seed_templates(30)
    @sessions = { 'Ada' => open_session }
    @sessions['Ada'].post rooms_path, params: { nickname: 'Ada' }
    @room = Room.live.last
    %w[Bob Cy].each do |name|
      @sessions[name] = open_session.tap { |s| s.post joins_path, params: { code: @room.code, nickname: name } }
    end
    @sessions['Ada'].post start_room_path(@room.code)
    @room.reload.advance! # an empty Round 1 goes through Standings
  end

  test 'every phone, a reload included, sees the Standings heading and a countdown' do
    assert @room.reload.standings?
    2.times do
      @sessions.each_value do |session|
        session.get room_path(@room.code)
        session.assert_select '#standings', text: /Standings/
        session.assert_select "#standings [data-controller='countdown']"
      end
    end
  end
end
