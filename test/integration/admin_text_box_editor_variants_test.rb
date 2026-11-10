require 'test_helper'

# The editor partial renders in two variants: :full (default) and :compact (stage only, for the phone layout).
class AdminTextBoxEditorVariantsTest < ActiveSupport::TestCase
  setup { @template = seed_templates(1).first }

  def render_editor(**locals)
    html = ApplicationController.render(partial: 'admin/templates/text_box_editor',
                                        locals: { save_url: '/save/here', image_url: '/img/here.png', boxes: @template.text_boxes,
                                                  name: @template.name, key: @template.id, **locals })
    Nokogiri::HTML.fragment(html)
  end

  test 'the default is the full editor' do
    editor = render_editor
    assert editor.at_css('[data-text-box-editor-target=stage]')
    assert editor.at_css('.tbe-preview-switch')
    assert editor.at_css('.tbe-actions')
    assert editor.at_css('[data-text-box-editor-target=rows]')
    assert editor.at_css('template [data-field=x]')
  end

  test 'the save URL, image and boxes come from the caller' do
    editor = render_editor(save_url: '/uploads/9/text_boxes', image_url: '/img/x.png', boxes: [])
    section = editor.at_css('[data-controller=text-box-editor]')
    assert_equal '/uploads/9/text_boxes', section['data-text-box-editor-url-value']
    assert_equal '/img/x.png', section['data-text-box-editor-image-value']
    assert_equal '[]', section['data-text-box-editor-boxes-value']
  end

  test 'compact keeps the stage and status but drops the preview switch, toolbar and numeric rows' do
    editor = render_editor(controls: :compact)
    assert editor.at_css('[data-text-box-editor-target=stage]')
    assert editor.at_css('[data-text-box-editor-target=overlay]')
    assert editor.at_css('[data-text-box-editor-target=status]')
    assert_nil editor.at_css('.tbe-preview-switch')
    assert_nil editor.at_css('[data-text-box-editor-target=fits]')
    assert_nil editor.at_css('.tbe-actions')
    assert_nil editor.at_css('[data-text-box-editor-target=rows]')
    assert_nil editor.at_css('[data-text-box-editor-target=rowTemplate]')
  end

  test 'phone is one column: stage, selected-box toolbar, add and reset, sample switch, in that order, with no move buttons' do
    editor = render_editor(controls: :phone)
    assert_equal 'phone', editor.at_css('[data-controller=text-box-editor]')['data-controls']
    order = ['[data-text-box-editor-target=stage]', '.tbe-selected-toolbar', '.tbe-actions', '.tbe-preview-switch'].map do |css|
      node = editor.at_css(css)
      assert node, "missing #{css}"
      editor.to_html.index(node.to_html)
    end
    assert_equal order.sort, order
    toolbar = editor.at_css('.tbe-selected-toolbar')
    assert toolbar.at_css('select[data-text-box-editor-target=selectedStyle]')
    assert_includes toolbar.text, 'Duplicate'
    assert_includes toolbar.text, 'Remove'
    assert_includes editor.at_css('.tbe-actions').text, '+ Text Box'
    assert_includes editor.at_css('.tbe-actions').text, 'Reset to top & bottom'
    assert_no_match(/Move earlier|Move later/, editor.text)
  end

  test 'phone puts the numeric rows in an Exact values disclosure, closed by default, after the sample switch' do
    editor = render_editor(controls: :phone)
    details = editor.at_css('details.tbe-exact')
    assert details
    assert_nil details['open']
    assert_equal 'Exact values', details.at_css('summary').text.strip
    assert details.at_css('[data-text-box-editor-target=rows]')
    assert editor.at_css('template[data-text-box-editor-target=rowTemplate] [data-field=angle]')
    assert_operator editor.to_html.index(details.to_html), :>, editor.to_html.index(editor.at_css('.tbe-preview-switch').to_html)
  end

  test 'full and compact have no Exact values disclosure' do
    assert_nil render_editor.at_css('details.tbe-exact')
    assert_nil render_editor(controls: :compact).at_css('details.tbe-exact')
  end

  test 'phone handles are at least 44px touch targets' do
    css = Rails.root.join('app/assets/stylesheets/text_box_stage.css').read
    assert_match(/\[data-controls=phone\] \.tbe-handle::after \{ inset: -15px; \}/, css) # 14px + 2*15
    assert_match(/\[data-controls=phone\] \.tbe-rotate::after \{ inset: -13px; \}/, css) # 18px + 2*13
  end
end
