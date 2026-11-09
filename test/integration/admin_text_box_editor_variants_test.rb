require 'test_helper'

# The editor partial renders in two variants: :full (default) and :compact (stage only, for the phone layout).
class AdminTextBoxEditorVariantsTest < ActiveSupport::TestCase
  setup { @template = seed_templates(1).first }

  def render_editor(**locals)
    html = ApplicationController.render(partial: 'admin/templates/text_box_editor',
                                        locals: { template: @template, **locals })
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
