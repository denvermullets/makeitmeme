require 'test_helper'

class AdminPacksTest < ActionDispatch::IntegrationTest
  def make_template(pack)
    Template.create!(memegen_id: "m-#{SecureRandom.hex(3)}", name: 'T', text_boxes: [], pack: pack)
  end

  test 'the Packs page is unreachable when signed out' do
    get admin_packs_path
    assert_redirected_to admin_sign_in_path
  end

  test 'lists every Pack with an accurate Template count, including empty ones' do
    classics = Pack.classics
    movies = Pack.create!(name: 'Movies')
    2.times { make_template(classics) }
    make_template(movies)
    Pack.custom
    sign_in_as_admin

    get admin_packs_path

    assert_response :success
    assert_select '[data-pack]', 3
    { 'Classics' => '2', 'Movies' => '1', 'Custom' => '0' }.each do |name, count|
      assert_select "[data-pack='#{name}']" do
        assert_select '.pack-name input[value=?]', name
        assert_select '.pack-count', count
      end
    end
  end

  test 'the admin layout links to the Packs page' do
    sign_in_as_admin

    get admin_root_path

    assert_select 'header a[href=?]', admin_packs_path
  end
end
