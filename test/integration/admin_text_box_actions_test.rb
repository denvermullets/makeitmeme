require 'test_helper'

class AdminTextBoxActionsTest < ActionDispatch::IntegrationTest
  STRIPS = [
    { 'x' => 0, 'y' => 0, 'w' => 1, 'h' => 0.2, 'angle' => 0, 'color' => 'white', 'font' => 'thick' },
    { 'x' => 0, 'y' => 0.8, 'w' => 1, 'h' => 0.2, 'angle' => 0, 'color' => 'white', 'font' => 'thick' }
  ].freeze

  setup do
    @template = seed_templates(1).first
    @template.update!(text_boxes: [STRIPS.first.merge('color' => 'black', 'font' => 'thin')])
    sign_in_as_admin
  end

  test 'the editor has the box action buttons and builds its rows from JS' do
    get admin_root_path(selected: @template.id)

    assert_response :success
    %w[addBox duplicateBox removeBox moveEarlier moveLater resetBoxes].each do |action|
      assert_select "button[data-action='text-box-editor##{action}']"
    end
    assert_select '[data-text-box-editor-target=rows]'
    assert_select 'template[data-text-box-editor-target=rowTemplate]'
    assert_select '[data-text-box-editor-target=rows] fieldset', 0
  end

  test 'the classic strips and a reordered list persist in order' do
    patch admin_template_text_boxes_path(@template), params: { text_boxes: STRIPS.reverse }, as: :json

    assert_response :success
    assert_equal [0.8, 0.0], @template.reload.text_boxes.map { |box| box['y'] }
  end

  test 'an empty list is still rejected and the stored boxes are kept' do
    patch admin_template_text_boxes_path(@template), params: { text_boxes: [] }, as: :json

    assert_response :unprocessable_content
    assert_equal 'black', @template.reload.text_boxes.first['color']
  end
end
