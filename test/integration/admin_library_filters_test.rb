require 'test_helper'

class AdminLibraryFiltersTest < ActionDispatch::IntegrationTest
  def make(name, **attrs)
    Template.create!({ memegen_id: "m-#{SecureRandom.hex(3)}", name: name, text_boxes: [] }.merge(attrs))
  end

  setup do
    @fresh = make('Fresh')
    @reviewed = make('Reviewed', reviewed_at: 1.day.ago)
    @hidden = make('Hidden One', hidden_at: 1.day.ago)
    @hidden_reviewed = make('Hidden Reviewed', hidden_at: 1.day.ago, reviewed_at: 1.day.ago)
    @upload = make('Upload', source_kind: 'upload')
    @upload_reviewed = make('Upload Reviewed', source_kind: 'upload', reviewed_at: 1.day.ago)
    sign_in_as_admin
  end

  def shown
    css_select('[data-template]').map { |li| li['data-template'].to_i }.sort
  end

  def chip_count(key)
    css_select("a[data-filter=#{key}] .chip-count").first.text.to_i
  end

  test 'new Templates default to memegen, unreviewed and not hidden' do
    assert_equal 'memegen', @fresh.source_kind
    assert_nil @fresh.reviewed_at
    assert_nil @fresh.hidden_at
  end

  test 'All shows everything, with a count on every chip' do
    get admin_root_path
    assert_equal Template.pluck(:id).sort, shown
    assert_equal([6, 2, 2, 2], %w[all review uploads hidden].map { |k| chip_count(k) })
  end

  test 'Needs review is unreviewed and not hidden' do
    get admin_root_path(filter: 'review')
    assert_equal [@fresh.id, @upload.id].sort, shown
    assert_select 'a[data-filter=review][aria-current=true]'
  end

  test 'Player uploads is source kind upload' do
    get admin_root_path(filter: 'uploads')
    assert_equal [@upload.id, @upload_reviewed.id].sort, shown
  end

  test 'Hidden is hidden_at set' do
    get admin_root_path(filter: 'hidden')
    assert_equal [@hidden.id, @hidden_reviewed.id].sort, shown
  end

  test 'an unknown filter falls back to All' do
    get admin_root_path(filter: 'bogus')
    assert_equal Template.count, shown.size
  end

  test 'filters combine with search and counts follow the search' do
    get admin_root_path(filter: 'uploads', q: 'reviewed')
    assert_equal [@upload_reviewed.id], shown
    assert_equal([3, 0, 1, 1], %w[all review uploads hidden].map { |k| chip_count(k) })
    assert_select 'form input[name=filter][value=uploads]'
  end

  test 'badges render for hidden, needs review and upload' do
    get admin_root_path
    assert_select "[data-template='#{@hidden.id}'] .badge-hidden"
    assert_select "[data-template='#{@hidden.id}'] .badge-review", 0
    assert_select "[data-template='#{@fresh.id}'] .badge-review"
    assert_select "[data-template='#{@upload.id}'] .badge-upload"
    assert_select "[data-template='#{@reviewed.id}'] .badge", 0
  end

  test 'template links keep the filter' do
    get admin_root_path(filter: 'hidden')
    assert_select 'a[data-template-link][href=?]', admin_root_path(selected: @hidden.id, filter: 'hidden')
  end
end
