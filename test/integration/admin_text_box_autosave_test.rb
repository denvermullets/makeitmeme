require 'test_helper'

class AdminTextBoxAutosaveTest < ActionDispatch::IntegrationTest
  VALID = {
    'x' => 0.5, 'y' => 0.1, 'w' => 0.4, 'h' => 0.3, 'angle' => 10, 'color' => 'black', 'font' => 'thin'
  }.freeze

  setup do
    @template = seed_templates(1).first
    @original = [{ 'x' => 0.0, 'y' => 0.0, 'w' => 1.0, 'h' => 0.2, 'angle' => 0.0,
                   'color' => 'white', 'font' => 'thick' }]
    @template.update!(text_boxes: @original, reviewed_at: nil)
    sign_in_as_admin
  end

  def patch_boxes(boxes)
    patch admin_template_text_boxes_path(@template), params: { text_boxes: boxes }, as: :json
  end

  def assert_rejected(boxes)
    patch_boxes(boxes)
    assert_response :unprocessable_content
    assert_predicate JSON.parse(response.body)['errors'], :present?
    @template.reload
    assert_equal @original, @template.text_boxes
    assert_nil @template.reviewed_at
  end

  test 'a valid save persists boxes in order and marks the Template reviewed' do
    second = VALID.merge('x' => 0.0, 'y' => 0.5, 'color' => 'white', 'font' => 'thick')
    patch_boxes([VALID, second])

    assert_response :success
    @template.reload
    assert_equal([0.5, 0.0], @template.text_boxes.map { |box| box['x'] })
    assert_equal 'black', @template.text_boxes.first['color']
    assert_not_nil @template.reviewed_at
  end

  test 'angles are normalised into (-180, 180]' do
    angles = { 190 => -170, -190 => 170, 540 => 180, -180 => 180, 360 => 0 }
    angles.each do |given, expected|
      patch_boxes([VALID.merge('angle' => given)])
      assert_response :success
      assert_in_delta expected, @template.reload.text_boxes.first['angle'], 0.001, "angle #{given}"
    end
  end

  test 'a box touching the image edge is accepted' do
    patch_boxes([VALID.merge('x' => 0.6, 'w' => 0.4)])
    assert_response :success
  end

  test 'out of bounds boxes are rejected' do
    assert_rejected([VALID.merge('x' => 0.7, 'w' => 0.4)])
    assert_rejected([VALID.merge('y' => 0.8, 'h' => 0.3)])
    assert_rejected([VALID.merge('x' => -0.1)])
    assert_rejected([VALID.merge('y' => -0.1)])
  end

  test 'zero or negative size is rejected' do
    assert_rejected([VALID.merge('w' => 0)])
    assert_rejected([VALID.merge('h' => -0.1)])
  end

  test 'a box smaller than the minimum size is rejected' do
    assert_rejected([VALID.merge('w' => 0.01)])
    assert_rejected([VALID.merge('h' => 0.019)])
  end

  test 'a save that includes the name renames the Template too' do
    patch admin_template_text_boxes_path(@template), params: { text_boxes: [VALID], name: '  Fresh name ' }, as: :json

    assert_response :success
    assert_equal 'Fresh name', JSON.parse(response.body)['name']
    assert_equal 'Fresh name', @template.reload.name
    assert_not_nil @template.reviewed_at
  end

  test 'a blank name rejects the whole save' do
    name = @template.name
    patch admin_template_text_boxes_path(@template), params: { text_boxes: [VALID], name: ' ' }, as: :json

    assert_response :unprocessable_content
    @template.reload
    assert_equal name, @template.name
    assert_equal @original, @template.text_boxes
    assert_nil @template.reviewed_at
  end

  test 'a save without a name leaves the name alone' do
    name = @template.name
    patch_boxes([VALID])
    assert_equal name, @template.reload.name
  end

  test 'renaming through the inspector form does not mark the Template reviewed' do
    patch admin_template_path(@template), params: { template: { name: 'Renamed' } }
    assert_equal 'Renamed', @template.reload.name
    assert_nil @template.reviewed_at
  end

  test 'an empty array is rejected' do
    assert_rejected([])
  end

  test 'a missing list is rejected' do
    patch admin_template_text_boxes_path(@template), params: { other: 1 }, as: :json
    assert_response :unprocessable_content
    assert_equal @original, @template.reload.text_boxes
  end

  test 'non-numeric values are rejected' do
    assert_rejected([VALID.merge('x' => 'abc')])
    assert_rejected([VALID.merge('w' => nil)])
    assert_rejected([VALID.merge('angle' => '10')])
    assert_rejected([VALID.except('h')])
  end

  test 'bad color or font is rejected' do
    assert_rejected([VALID.merge('color' => 'red')])
    assert_rejected([VALID.merge('font' => 'bold')])
  end

  test 'one bad box rejects the whole save' do
    assert_rejected([VALID, VALID.merge('w' => 0)])
  end

  test 'requires the Admin' do
    delete admin_sign_out_path
    patch_boxes([VALID])
    assert_response :unauthorized
    assert_equal @original, @template.reload.text_boxes
  end

  test 'the panel hands the stored boxes to the editor, which builds the numeric rows in JS' do
    first = @original.first.merge('x' => 0.25, 'angle' => -15.0, 'color' => 'black', 'font' => 'thin')
    @template.update!(text_boxes: [first, VALID])
    get admin_root_path(selected: @template.id)

    assert_select 'turbo-frame#template_panel [data-text-box-editor]' do |editor|
      assert_equal [first, VALID], JSON.parse(editor.first['data-text-box-editor-boxes-value'])
      assert_select 'template input[data-field=x][data-unit=percent]'
      assert_select 'template input[data-field=angle][data-unit=degrees]'
      assert_select 'template option[value=black]'
      assert_select '[data-text-box-editor-target=status]'
    end
  end
end
