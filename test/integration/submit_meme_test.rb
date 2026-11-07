require 'test_helper'

# Submitting a Meme over the web, and what the Player sees afterwards.
class SubmitMemeTest < ActionDispatch::IntegrationTest
  setup do
    seed_templates(30).each { |template| template.update!(text_boxes: [{ 'x' => 0, 'y' => 0, 'w' => 1, 'h' => 0.3 }]) }
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

  def signed_id
    ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture('drake.png')), filename: 'meme.png',
                                           content_type: 'image/png').signed_id
  end

  def bobs_template_id
    @room.reload.hand_for(@room.player_for(Player.find_by(nickname: 'Bob').browser_token)).template_ids.first
  end

  def submit(signed_id: self.signed_id, template_id: bobs_template_id)
    @bob.post room_memes_path(@room.code), params: { signed_id:, template_id:, captions: ['hello'] }, as: :json
  end

  test 'the editor knows where to upload, where to submit and when time is up' do
    @bob.assert_select '[data-controller~="meme-editor"][data-meme-editor-submit-url-value=?]',
                       room_memes_path(@room.code)
    @bob.assert_select '[data-meme-editor-direct-upload-url-value=?]', rails_direct_uploads_path
    @bob.assert_select '[data-meme-editor-deadline-value]'
  end

  test 'submitting creates the Meme and answers with its image' do
    submit

    @bob.assert_response :created
    meme = Meme.last
    assert_equal ['hello'], meme.caption_texts
    assert_equal rails_storage_proxy_path(meme.image), JSON.parse(@bob.response.body)['image_url']
  end

  test 'a reload after submitting shows the submitted state, not the editor' do
    submit
    @bob.get room_path(@room.code)

    @bob.assert_select '[data-controller~="meme-editor"]', count: 0
    @bob.assert_select '#hand .meme-submitted img[src=?]', rails_storage_proxy_path(Meme.last.image)
    @bob.assert_select '#hand', text: /Meme submitted/
  end

  test 'a rejected submission answers 422 with the reason' do
    submit
    submit

    @bob.assert_response :unprocessable_content
    assert_includes JSON.parse(@bob.response.body)['errors'], 'You already submitted a Meme this Round'
    assert_equal 1, Meme.count
  end

  test 'someone without a seat cannot submit' do
    stranger = open_session
    stranger.post room_memes_path(@room.code), params: { signed_id:, template_id: 1 }, as: :json

    stranger.assert_response :unauthorized
    assert_equal 0, Meme.count
  end
end
