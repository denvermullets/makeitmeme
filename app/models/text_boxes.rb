# Validates and normalises an ordered array of Text Boxes: the one validator Admin edits and Player uploads share.
#
#   result = TextBoxes.check(raw)
#   result.valid?  # => true/false
#   result.boxes   # => normalised boxes (string keys, angle in (-180, 180]); empty when invalid
#   result.errors  # => ["Box 1: width and height must be greater than 0", ...]
module TextBoxes
  COLORS = %w[white black].freeze
  FONTS = %w[thick thin].freeze
  EPSILON = 1e-6
  # The top and bottom strips a new Upload draft starts with; mirrors CLASSIC_STRIPS in text_box_list.js.
  TOP_AND_BOTTOM = [
    { 'x' => 0.0, 'y' => 0.0, 'w' => 1.0, 'h' => 0.2, 'angle' => 0.0, 'color' => 'white', 'font' => 'thick' },
    { 'x' => 0.0, 'y' => 0.8, 'w' => 1.0, 'h' => 0.2, 'angle' => 0.0, 'color' => 'white', 'font' => 'thick' }
  ].freeze
  # Smallest width or height, as a fraction of the image (about 12px on a 600px stage).
  MIN_SIZE = 0.02
  GEOMETRY = %w[x y w h].freeze
  LABELS = { 'x' => 'x', 'y' => 'y', 'w' => 'width', 'h' => 'height', 'angle' => 'angle' }.freeze

  Result = Data.define(:boxes, :errors) do
    def valid? = errors.empty?
  end

  module_function

  def check(raw)
    return Result.new([], ['Text Boxes must be a list']) unless raw.is_a?(Array)
    return Result.new([], ['Add at least one Text Box']) if raw.empty?

    errors = []
    boxes = raw.each_with_index.map { |box, index| check_box(box, index + 1, errors) }
    errors.empty? ? Result.new(boxes, []) : Result.new([], errors)
  end

  # Maps any angle onto (-180, 180].
  def normalize_angle(angle)
    wrapped = ((angle + 180.0) % 360.0) - 180.0
    wrapped = 180.0 if wrapped <= -180.0
    wrapped.round(4)
  end

  def check_box(box, number, errors)
    box = box.to_unsafe_h if box.respond_to?(:to_unsafe_h)
    unless box.is_a?(Hash)
      errors << "Box #{number}: must be an object"
      return nil
    end
    box = box.stringify_keys
    problems = type_problems(box).presence || range_problems(box)
    errors.concat(problems.map { |problem| "Box #{number}: #{problem}" })
    problems.empty? ? normalized(box) : nil
  end

  def type_problems(box)
    problems = (GEOMETRY + ['angle']).reject { |key| finite_number?(box[key]) }
                                     .map { |key| "#{LABELS[key]} must be a finite number" }
    problems << "color must be one of #{COLORS.join(', ')}" unless COLORS.include?(box['color'])
    problems << "font must be one of #{FONTS.join(', ')}" unless FONTS.include?(box['font'])
    problems
  end

  def range_problems(box) # rubocop:disable Metrics/CyclomaticComplexity
    x, y, w, h = GEOMETRY.map { |key| box[key].to_f }
    problems = []
    problems << 'x and y must not be negative' if x < -EPSILON || y < -EPSILON
    problems << "width and height must be at least #{MIN_SIZE}" if w < MIN_SIZE - EPSILON || h < MIN_SIZE - EPSILON
    problems << 'must stay inside the image' if x + w > 1 + EPSILON || y + h > 1 + EPSILON
    problems
  end

  def normalized(box)
    box.slice(*GEOMETRY).transform_values(&:to_f).merge(
      'angle' => normalize_angle(box['angle'].to_f), 'color' => box['color'], 'font' => box['font']
    )
  end

  def finite_number?(value)
    value.is_a?(Numeric) && value.to_f.finite?
  end
end
