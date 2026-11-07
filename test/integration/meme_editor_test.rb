require 'test_helper'

# The Meme editor as a Player receives it: their Hand's Templates, Text Box data and same-origin image URLs.
class MemeEditorTest < ActionDispatch::IntegrationTest
  BOX = { 'x' => 0.1, 'y' => 0.2, 'w' => 0.5, 'h' => 0.25, 'angle' => 0, 'color' => 'white', 'font' => 'thick' }.freeze

  setup do
    seed_templates(30).each { |template| template.update!(text_boxes: [BOX, BOX.merge('y' => 0.7)]) }
    host = open_session
    host.post rooms_path, params: { nickname: 'Ada' }
    @room = Room.live.last
    @bob = open_session
    @bob.post joins_path, params: { code: @room.code, nickname: 'Bob' }
    @cy = open_session
    @cy.post joins_path, params: { code: @room.code, nickname: 'Cy' }
    host.post start_room_path(@room.code)
    @bob.get room_path(@room.code)
  end

  def editor_hand
    element = @bob.css_select('[data-controller~="meme-editor"]').first
    JSON.parse(element['data-meme-editor-hand-value'])
  end

  test 'the editor carries the Players own ten Templates with Text Boxes and proxy image URLs' do
    @bob.assert_select '[data-controller~="meme-editor"]', count: 1
    @bob.assert_select '[data-meme-editor-target="canvas"]'
    @bob.assert_select '[data-meme-editor-target="fields"]'

    mine = @room.reload.hand_for(@room.players.find_by(nickname: 'Bob')).template_ids

    assert_equal mine, editor_hand.pluck('id')
    editor_hand.each do |t|
      assert_equal 2, t['boxes'].length
      assert_equal %w[angle color font h w x y], t['boxes'].first.keys.sort
      assert_match %r{\A/rails/active_storage/blobs/proxy/}, t['url']
    end
  end

  test 'a Template image URL is same-origin and served' do
    @bob.get editor_hand.first['url']
    @bob.assert_response :success
  end
end
