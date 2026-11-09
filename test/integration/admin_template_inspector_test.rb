require 'test_helper'

class AdminTemplateInspectorTest < ActionDispatch::IntegrationTest
  setup do
    @template = seed_templates(1).first
    @template.update!(name: 'Drake', reviewed_at: nil)
    sign_in_as_admin
  end

  def make_meme(template, room)
    game = room.games.last
    Meme.new(round: game.rounds.first, game_player: game.game_players.first, template:, caption_texts: []).tap do |meme|
      meme.image.attach(io: File.open(file_fixture('drake.png')), filename: 'meme.png', content_type: 'image/png')
      meme.save!
    end
  end

  test 'the inspector shows image, editable name, source, uses and reviewed state' do
    seed_templates(Hand::SIZE)
    room = room_with_players
    room.start(by: room.player_for('ada'))
    make_meme(@template, room)

    get admin_root_path(selected: @template.id)

    assert_select 'turbo-frame#template_panel [data-inspector]' do
      assert_select 'img'
      assert_select 'input[name="template[name]"][value=?]', 'Drake'
      assert_select '[data-inspector-source]', text: /memegen import/
      assert_select '[data-inspector-uses]', text: /1 Meme/
      assert_select '[data-inspector-reviewed]', text: /Needs review/
    end
  end

  test 'an upload shows as a Player upload' do
    @template.update!(source_kind: 'upload')
    get admin_root_path(selected: @template.id)
    assert_select '[data-inspector-source]', text: /Player upload/
  end

  test 'a rename persists and leaves reviewed_at alone' do
    reviewed = Time.zone.parse('2026-01-02 03:04:05')
    @template.update!(reviewed_at: reviewed)

    patch admin_template_path(@template), params: { template: { name: 'Hotline Bling' } }

    assert_redirected_to admin_root_path(selected: @template.id)
    assert_equal 'Hotline Bling', @template.reload.name
    assert_equal reviewed, @template.reviewed_at
  end

  test 'renaming an unreviewed Template does not mark it reviewed' do
    patch admin_template_path(@template), params: { template: { name: 'Renamed' } }
    assert_nil @template.reload.reviewed_at
  end

  test 'a blank name is rejected with an error and not saved' do
    patch admin_template_path(@template), params: { template: { name: '  ' } }

    assert_response :unprocessable_content
    assert_select 'turbo-frame#template_panel .errors li', text: /Name can't be blank/
    assert_equal 'Drake', @template.reload.name
  end

  test 'Mark reviewed sets reviewed_at and the Template leaves Needs review' do
    get admin_root_path(filter: 'review')
    assert_select "[data-template='#{@template.id}']"

    post review_admin_template_path(@template)

    assert_redirected_to admin_root_path(selected: @template.id)
    assert_not_nil @template.reload.reviewed_at
    assert_equal 'Drake', @template.name
    get admin_root_path(filter: 'review')
    assert_select "[data-template='#{@template.id}']", 0
  end

  test 'Mark reviewed is not offered once reviewed' do
    @template.update!(reviewed_at: Time.current)
    get admin_root_path(selected: @template.id)
    assert_select 'form[action=?]', review_admin_template_path(@template), 0
    assert_select '[data-inspector-reviewed]', text: /Reviewed/
  end

  test 'only the Admin can rename or review' do
    delete admin_sign_out_path
    patch admin_template_path(@template), params: { template: { name: 'Hax' } }
    assert_redirected_to admin_sign_in_path
    post review_admin_template_path(@template)
    assert_redirected_to admin_sign_in_path
    assert_equal 'Drake', @template.reload.name
    assert_nil @template.reviewed_at
  end
end
