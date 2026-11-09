require 'test_helper'

class AdminDeleteTemplateTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @doomed, @kept = seed_templates(2)
  end

  def started_room
    seed_templates(Hand::SIZE)
    room = room_with_players
    room.start(by: room.player_for('ada'))
    room
  end

  def make_meme(template, room)
    game = room.games.last
    Meme.new(round: game.rounds.first, game_player: game.game_players.first, template:, caption_texts: []).tap do |meme|
      meme.image.attach(io: File.open(file_fixture('drake.png')), filename: 'meme.png', content_type: 'image/png')
      meme.save!
    end
  end

  def blob_id
    ActiveStorage::Blob.create_and_upload!(io: File.open(file_fixture('drake.png')), filename: 'm.png',
                                           content_type: 'image/png').signed_id
  end

  test 'the panel offers a delete that confirms with the Memes-used count' do
    make_meme(@doomed, started_room)
    sign_in_as_admin

    get admin_root_path(selected: @doomed.id)
    assert_select 'turbo-frame#template_panel form[action=?]', admin_template_path(@doomed) do
      assert_select 'input[name=_method][value=delete]'
      assert_select 'button[data-turbo-confirm*=?]', '1 Meme'
      assert_select 'button[data-turbo-confirm*=?]', 'kept'
    end
  end

  test 'deleting removes the Template and its image from the grid and library' do
    sign_in_as_admin
    image_blob_id = @doomed.image.blob.id

    perform_enqueued_jobs { delete admin_template_path(@doomed) }

    assert_redirected_to admin_root_path
    assert_not Template.exists?(@doomed.id)
    assert_not ActiveStorage::Blob.exists?(image_blob_id)
    follow_redirect!
    assert_select "[data-template='#{@doomed.id}']", 0
    assert_select "[data-template='#{@kept.id}']", 1
  end

  test 'Memes made from it keep their image with template_id nulled' do
    meme = make_meme(@doomed, started_room)
    sign_in_as_admin

    perform_enqueued_jobs { delete admin_template_path(@doomed) }

    meme.reload
    assert_nil meme.template_id
    assert ActiveStorage::Blob.exists?(meme.image.blob.id)
  end

  test 'a Hand holding the deleted id renders without it and stays usable' do
    seed_templates(Hand::SIZE)
    host = open_session
    host.post rooms_path, params: { nickname: 'Ada' }
    room = Room.live.last
    Room.join(code: room.code, nickname: 'Bob', browser_token: 'bob')
    Room.join(code: room.code, nickname: 'Cy', browser_token: 'cy')
    ada = room.host
    room.start(by: ada)
    gone_id, remaining_id = room.hand_for(ada).template_ids.first(2)
    sign_in_as_admin
    perform_enqueued_jobs { delete admin_template_path(gone_id) }

    host.get room_path(room.code)
    host.assert_response :success
    hand_json = JSON.parse(host.css_select('[data-meme-editor-hand-value]').first['data-meme-editor-hand-value'])
    assert_equal Hand::SIZE - 1, hand_json.size
    assert_not_includes hand_json.pluck('id'), gone_id

    meme = room.submit_meme(by: ada, signed_id: blob_id, template_id: remaining_id, captions: [])
    assert_equal remaining_id, meme.template_id
  end

  test 'submitting the deleted Template is refused as not in the Hand' do
    room = started_room
    ada = room.player_for('ada')
    gone_id = room.hand_for(ada).template_ids.first
    sign_in_as_admin
    perform_enqueued_jobs { delete admin_template_path(gone_id) }

    assert_raises(ActiveRecord::RecordInvalid) do
      room.submit_meme(by: ada, signed_id: blob_id, template_id: gone_id, captions: [])
    end
  end

  test 'only the Admin can delete' do
    delete admin_template_path(@doomed)
    assert_redirected_to admin_sign_in_path
    assert Template.exists?(@doomed.id)
  end
end
