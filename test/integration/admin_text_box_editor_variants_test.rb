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
end
