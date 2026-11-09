require 'test_helper'

class HostPackTogglesTest < ActionDispatch::IntegrationTest
  setup do
    seed_templates(12)
    @pack = Pack.create!(name: 'Spicy')
    @host = open_session
    @host.post rooms_path, params: { nickname: 'Ada' }
    @room = Room.live.last
    @bob = open_session
    @bob.post joins_path, params: { code: @room.code, nickname: 'Bob' }
    open_session.post joins_path, params: { code: @room.code, nickname: 'Cy' }
  end

  test 'Waiting lists every Pack with its dealable count' do
    @host.get room_path(@room.code)
    @host.assert_select "#packs [data-pack='#{@pack.id}'] .pack-count", '0'
    @host.assert_select "#packs [data-pack='#{Pack.classics.id}'] .pack-count", '12'
  end

  test 'the Host toggles a Pack off and on' do
    @host.post toggle_room_pack_path(@room.code, @pack, on: 0)
    assert_equal [@pack.id], @room.reload.off_pack_ids
    @host.follow_redirect!
    @host.assert_select "[data-pack='#{@pack.id}'][data-pack-on='false']"
    @host.post toggle_room_pack_path(@room.code, @pack, on: 1)
    assert_empty @room.reload.off_pack_ids
  end

  test 'a non-Host toggle is refused' do
    @bob.post toggle_room_pack_path(@room.code, @pack, on: 0)
    @bob.assert_response :unprocessable_content
    assert_empty @room.reload.off_pack_ids
  end

  test 'a toggle during Captioning is refused' do
    @host.post start_room_path(@room.code)
    @host.post toggle_room_pack_path(@room.code, @pack, on: 0)
    @host.assert_response :unprocessable_content
    assert_empty @room.reload.off_pack_ids
  end

  test 'Start refuses once Packs off leave too few Templates' do
    @host.post toggle_room_pack_path(@room.code, Pack.classics, on: 0)
    @host.post start_room_path(@room.code)
    @host.assert_response :unprocessable_content
    assert @room.reload.waiting?
  end
end
