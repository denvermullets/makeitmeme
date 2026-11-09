require 'test_helper'

class AdminLibraryGridTest < ActionDispatch::IntegrationTest
  BOX = { x: 0, y: 0, w: 1, h: 0.2, angle: 0, color: 'white', font: 'thick' }.freeze

  def make_template(name, boxes: 0)
    Template.create!(memegen_id: "m-#{SecureRandom.hex(3)}", name: name,
                     text_boxes: Array.new(boxes) { BOX }).tap do |t|
      t.image.attach(io: File.open(file_fixture('drake.png')), filename: 'drake.png', content_type: 'image/png')
    end
  end

  test 'the grid is unreachable when signed out' do
    get admin_root_path
    assert_redirected_to admin_sign_in_path
  end

  test 'lists every Template with name, box count and proxied image' do
    drake = make_template('Drake', boxes: 2)
    make_template('Distracted Boyfriend', boxes: 3)
    sign_in_as_admin

    get admin_root_path
    assert_response :success
    assert_select 'turbo-frame#library_grid [data-template]', 2
    assert_select "[data-template='#{drake.id}']" do
      assert_select '.template-name', 'Drake'
      assert_select '.box-count', '2'
      assert_select 'img[src^=?]', '/rails/active_storage/blobs/proxy/'
    end
  end

  test 'search is case-insensitive partial and reflected in the search form' do
    make_template('Drake')
    make_template('Distracted Boyfriend')
    sign_in_as_admin

    get admin_root_path(q: 'dRAk')
    assert_select '[data-template]', 1
    assert_select '.template-name', 'Drake'
    assert_select 'form[method=get][action=?] input[name=q][value=dRAk]', admin_root_path
  end

  test 'search matching nothing says so' do
    make_template('Drake')
    sign_in_as_admin

    get admin_root_path(q: 'zzz')
    assert_select '[data-template]', 0
    assert_select '.empty', /No Templates/
  end

  test 'search treats LIKE wildcards literally' do
    make_template('Drake')
    sign_in_as_admin

    get admin_root_path(q: '%')
    assert_select '[data-template]', 0
  end

  test 'selecting a Template marks it and loads the side frame keyed to it' do
    drake = make_template('Drake')
    other = make_template('Other')
    sign_in_as_admin

    get admin_root_path(selected: drake.id)
    assert_select "[data-template='#{drake.id}'][aria-current=true]"
    assert_select "[data-template='#{other.id}'][aria-current]", 0
    assert_select "turbo-frame#template_panel[data-template-id='#{drake.id}']"
  end

  test 'with nothing selected the side frame is a placeholder' do
    make_template('Drake')
    sign_in_as_admin

    get admin_root_path
    assert_select 'turbo-frame#template_panel .placeholder'
  end

  test 'template links keep the search in the URL' do
    drake = make_template('Drake')
    sign_in_as_admin

    get admin_root_path(q: 'dra')
    assert_select 'a[data-template-link][href=?]', admin_root_path(q: 'dra', selected: drake.id)
  end
end
