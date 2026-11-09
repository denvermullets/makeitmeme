require 'test_helper'

class AdminTextBoxStageTest < ActionDispatch::IntegrationTest
  setup do
    @template = seed_templates(1).first
    @template.update!(text_boxes: [{ 'x' => 0.1, 'y' => 0.1, 'w' => 0.5, 'h' => 0.2, 'angle' => 0.0,
                                     'color' => 'white', 'font' => 'thick' }])
    sign_in_as_admin
  end

  test 'the editor mounts a stage that takes the image and boxes as values' do
    get admin_root_path(selected: @template.id)

    assert_response :success
    assert_select '[data-controller~=text-box-editor]' do |editor|
      assert_includes editor.first['data-text-box-editor-image-value'], 'rails/active_storage'
    end
    assert_select '[data-text-box-editor-target=stage] img[data-text-box-editor-target=image]'
    assert_select '[data-text-box-editor-target=overlay]'
  end

  test 'the editor offers an off/short/medium/long sample-text switch and a preview canvas' do
    get admin_root_path(selected: @template.id)

    assert_select '[data-text-box-editor-target=stage] canvas[data-text-box-editor-target=preview]'
    assert_select 'input[type=radio][data-sample-level]', 4
    assert_select 'input[data-sample-level=off][checked]'
    %w[short medium long].each { |level| assert_select "input[data-sample-level=#{level}]" }
    assert_select '[data-text-box-editor-target=fits]'
  end

  test 'a sample level sent with a save is ignored and never stored on the Template' do
    patch admin_template_text_boxes_path(@template), as: :json,
                                                     params: { text_boxes: @template.text_boxes, sample_level: 'long' }

    assert_response :success
    assert_equal %w[angle color font h w x y], @template.reload.text_boxes.first.keys.sort
  end
end
