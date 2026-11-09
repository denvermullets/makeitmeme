require 'test_helper'

class AdminHideTemplateTest < ActionDispatch::IntegrationTest
  setup { @template, @other = seed_templates(2) }

  test 'the panel offers Hide from Hands, and Unhide once hidden' do
    sign_in_as_admin

    get admin_root_path(selected: @template.id)
    assert_select 'turbo-frame#template_panel form[action^=?]', admin_template_hiding_path(@template) do
      assert_select 'button', 'Hide from Hands'
    end

    @template.update!(hidden_at: Time.current)
    get admin_root_path(selected: @template.id)
    assert_select 'turbo-frame#template_panel form[action^=?]', admin_template_hiding_path(@template) do
      assert_select 'input[name=_method][value=delete]'
      assert_select 'button', 'Unhide'
    end
  end

  test 'hiding persists, and the Hidden filter and badge show it at once' do
    sign_in_as_admin

    post admin_template_hiding_path(@template, filter: 'hidden', selected: @template.id)

    assert @template.reload.hidden?
    assert_redirected_to admin_root_path(selected: @template.id, filter: 'hidden')
    follow_redirect!
    assert_select '[data-filter=hidden] .chip-count', '1'
    assert_select "[data-template='#{@template.id}'] .badge-hidden"
    assert_select "[data-template='#{@other.id}']", 0
  end

  test 'unhiding clears hidden_at' do
    @template.update!(hidden_at: Time.current)
    sign_in_as_admin

    delete admin_template_hiding_path(@template)

    assert_not @template.reload.hidden?
    assert_redirected_to admin_root_path
  end

  test 'hiding twice keeps the original timestamp' do
    sign_in_as_admin
    post admin_template_hiding_path(@template)
    first = @template.reload.hidden_at
    post admin_template_hiding_path(@template)
    assert_equal first, @template.reload.hidden_at
  end

  test 'only the Admin can hide or unhide' do
    post admin_template_hiding_path(@template)
    assert_redirected_to admin_sign_in_path
    assert_not @template.reload.hidden?

    @template.update!(hidden_at: Time.current)
    delete admin_template_hiding_path(@template)
    assert_redirected_to admin_sign_in_path
    assert @template.reload.hidden?
  end
end
