require 'test_helper'

class HostCaptioningPresetTest < ActionDispatch::IntegrationTest
  setup do
    seed_templates(12)
    @host = open_session
    @host.post rooms_path, params: { nickname: 'Ada' }
    @room = Room.live.last
    @bob = open_session
    @bob.post joins_path, params: { code: @room.code, nickname: 'Bob' }
    open_session.post joins_path, params: { code: @room.code, nickname: 'Cy' }
  end

  test 'the Host sees three choices with Normal selected' do
    @host.get room_path(@room.code)
    @host.assert_select "#captioning_preset[data-preset='normal']"
    @host.assert_select '#captioning_preset button', 3
    @host.assert_select "#captioning_preset [data-preset-option='normal'][aria-current='true']"
    %w[quick normal chill].each { |p| @host.assert_select "#captioning_preset [data-preset-option='#{p}']" }
  end

  test 'other Players see the current preset read-only' do
    @bob.get room_path(@room.code)
    @bob.assert_select "#captioning_preset[data-preset='normal']"
    @bob.assert_select '#captioning_preset button', 0
    @bob.assert_select '#captioning_preset', /Normal/
  end

  test 'the Host changes the preset and everyone sees it' do
    @host.post room_captioning_preset_path(@room.code, preset: 'chill')
    assert @room.reload.chill?
    @host.follow_redirect!
    @host.assert_select "#captioning_preset[data-preset='chill']"
    @bob.get room_path(@room.code)
    @bob.assert_select "#captioning_preset[data-preset='chill']"
  end

  test 'a non-Host change is refused' do
    @bob.post room_captioning_preset_path(@room.code, preset: 'quick')
    @bob.assert_response :unprocessable_content
    assert @room.reload.normal?
  end

  test 'an unknown preset is refused' do
    @host.post room_captioning_preset_path(@room.code, preset: 'turbo')
    @host.assert_response :unprocessable_content
    assert @room.reload.normal?
  end

  test 'a change during Captioning is refused' do
    @host.post start_room_path(@room.code)
    @host.post room_captioning_preset_path(@room.code, preset: 'quick')
    @host.assert_response :unprocessable_content
    assert @room.reload.normal?
  end
end
