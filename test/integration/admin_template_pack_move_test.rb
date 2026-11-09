require 'test_helper'

class AdminTemplatePackMoveTest < ActionDispatch::IntegrationTest
  def make(name, pack, **attrs)
    Template.create!({ memegen_id: "m-#{SecureRandom.hex(3)}", name:, text_boxes: [], pack: }.merge(attrs))
  end

  setup do
    @classics = Pack.classics
    @fun = Pack.create!(name: 'Fun')
    @drake = make('Drake', @classics, reviewed_at: nil)
    @doge = make('Doge', @classics, hidden_at: 1.day.ago, reviewed_at: 2.days.ago)
    @cat = make('Cat', @fun)
    @fun_upload = make('Cat Upload', @fun, source_kind: 'upload')
    sign_in_as_admin
  end

  def shown = css_select('[data-template]').map { |li| li['data-template'].to_i }.sort
  def chip_count(key) = css_select("a[data-filter=#{key}] .chip-count").first.text.to_i

  test 'the inspector shows the current Pack and offers every Pack' do
    get admin_root_path(selected: @drake.id)
    assert_select 'select[name="template[pack_id]"]' do
      assert_select 'option', 2
      assert_select 'option[selected][value=?]', @classics.id.to_s
    end
  end

  test 'moving a Template changes its Pack only, not reviewed or hidden state' do
    reviewed_at = @doge.reviewed_at
    patch admin_template_path(@doge), params: { template: { pack_id: @fun.id } }
    assert_redirected_to admin_root_path(selected: @doge.id)
    @doge.reload
    assert_equal @fun, @doge.pack
    assert_equal 'Doge', @doge.name
    assert @doge.hidden?
    assert_in_delta reviewed_at, @doge.reviewed_at, 1
  end

  test 'a moved Template appears under its new Pack filter and leaves the old one' do
    patch admin_template_path(@drake), params: { template: { pack_id: @fun.id } }
    get admin_root_path(pack: @fun.id)
    assert_includes shown, @drake.id
    get admin_root_path(pack: @classics.id)
    assert_not_includes shown, @drake.id
  end

  test 'a move keeps the search, filter and Pack in the redirect' do
    patch admin_template_path(@drake, q: 'dra', filter: 'review', pack: @classics.id),
          params: { template: { pack_id: @fun.id } }
    assert_redirected_to admin_root_path(q: 'dra', filter: 'review', pack: @classics.id, selected: @drake.id)
  end

  test 'the Pack filter combines with search and chips, and chip counts respect it' do
    get admin_root_path(pack: @fun.id)
    assert_equal [@cat.id, @fun_upload.id].sort, shown
    assert_equal([2, 2, 1, 0], %w[all review uploads hidden].map { |k| chip_count(k) })

    get admin_root_path(pack: @fun.id, q: 'upload')
    assert_equal [@fun_upload.id], shown

    get admin_root_path(pack: @fun.id, filter: 'uploads')
    assert_equal [@fun_upload.id], shown

    get admin_root_path(pack: @classics.id, filter: 'hidden')
    assert_equal [@doge.id], shown
    get admin_root_path(pack: @fun.id, filter: 'hidden')
    assert_empty shown
  end

  test 'links and the filter control carry the Pack' do
    get admin_root_path(pack: @fun.id, selected: @cat.id)
    assert_select 'select[name=pack] option[selected][value=?]', @fun.id.to_s
    assert_select "a[data-filter=review][href*='pack=#{@fun.id}']"
    assert_select "li[data-template='#{@cat.id}'] a[href*='pack=#{@fun.id}']"
  end

  test 'Pack counts update after a move' do
    patch admin_template_path(@drake), params: { template: { pack_id: @fun.id } }
    assert_equal 3, @fun.templates.count
    assert_equal 1, @classics.templates.count
  end
end
