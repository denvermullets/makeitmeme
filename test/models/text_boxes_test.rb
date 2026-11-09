require 'test_helper'

class TextBoxesTest < ActiveSupport::TestCase
  BOX = { 'x' => 0.1, 'y' => 0.1, 'w' => 0.5, 'h' => 0.2, 'angle' => 0, 'color' => 'white', 'font' => 'thick' }.freeze

  test 'valid boxes come back normalised and in order' do
    result = TextBoxes.check([BOX, BOX.merge('x' => 0.2, 'angle' => 270)])
    assert_predicate result, :valid?
    assert_equal([0.1, 0.2], result.boxes.map { |box| box['x'] })
    assert_equal(-90.0, result.boxes.last['angle'])
  end

  test 'symbol keys and integers are accepted' do
    assert_predicate TextBoxes.check([{ x: 0, y: 0, w: 1, h: 1, angle: 0, color: 'black', font: 'thin' }]), :valid?
  end

  test 'a tiny overshoot within epsilon is allowed' do
    assert_predicate TextBoxes.check([BOX.merge('w' => 0.9 + 1e-9)]), :valid?
  end

  test 'infinite and NaN values are rejected' do
    assert_not_predicate TextBoxes.check([BOX.merge('x' => Float::INFINITY)]), :valid?
    assert_not_predicate TextBoxes.check([BOX.merge('x' => Float::NAN)]), :valid?
  end

  test 'non-list and non-object input is rejected' do
    assert_not_predicate TextBoxes.check(nil), :valid?
    assert_not_predicate TextBoxes.check(['box']), :valid?
  end

  test 'errors name the box' do
    result = TextBoxes.check([BOX, BOX.merge('color' => 'red')])
    assert_match(/Box 2: color/, result.errors.first)
  end
end
