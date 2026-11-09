require 'test_helper'

class AdminPackManagementTest < ActionDispatch::IntegrationTest
  def make_template(pack)
    Template.create!(memegen_id: "m-#{SecureRandom.hex(3)}", name: 'T', text_boxes: [], pack: pack)
  end

  test 'every management action is refused when signed out' do
    pack = Pack.create!(name: 'Movies')

    post admin_packs_path, params: { pack: { name: 'X' } }
    assert_redirected_to admin_sign_in_path
    patch admin_pack_path(pack), params: { pack: { name: 'Y' } }
    assert_redirected_to admin_sign_in_path
    delete admin_pack_path(pack)
    assert_redirected_to admin_sign_in_path

    assert_equal ['Movies'], Pack.pluck(:name)
  end

  test 'creates a Pack by name' do
    sign_in_as_admin

    post admin_packs_path, params: { pack: { name: 'Movies' } }

    assert_redirected_to admin_packs_path
    assert Pack.exists?(name: 'Movies')
  end

  test 'creating a Pack whose name differs only by case shows an error' do
    Pack.create!(name: 'Movies')
    sign_in_as_admin

    post admin_packs_path, params: { pack: { name: 'movies' } }

    assert_response :unprocessable_content
    assert_select '.errors li', /taken/i
    assert_equal 1, Pack.count
  end

  test 'renames a Pack, including Custom' do
    movies = Pack.create!(name: 'Movies')
    custom = Pack.custom
    sign_in_as_admin

    patch admin_pack_path(movies), params: { pack: { name: 'Films' } }
    patch admin_pack_path(custom), params: { pack: { name: 'Mine' } }

    assert_equal 'Films', movies.reload.name
    assert_equal 'Mine', custom.reload.name
    assert custom.custom?
  end

  test 'renaming onto another Pack name shows an error and changes nothing' do
    Pack.create!(name: 'Movies')
    other = Pack.create!(name: 'Games')
    sign_in_as_admin

    patch admin_pack_path(other), params: { pack: { name: 'MOVIES' } }

    assert_response :unprocessable_content
    assert_select '.errors li', /taken/i
    assert_equal 'Games', other.reload.name
  end

  test 'deleting a Pack that still has Templates is refused with a message' do
    movies = Pack.create!(name: 'Movies')
    make_template(movies)
    sign_in_as_admin

    delete admin_pack_path(movies)

    assert_response :unprocessable_content
    assert_select '.errors li', /still has Templates/
    assert Pack.exists?(movies.id)
  end

  test 'deletes an empty Pack, including Classics' do
    movies = Pack.create!(name: 'Movies')
    classics = Pack.classics
    sign_in_as_admin

    delete admin_pack_path(movies)
    delete admin_pack_path(classics)

    assert_redirected_to admin_packs_path
    assert_not Pack.exists?(movies.id)
    assert_not Pack.exists?(classics.id)
  end

  test 'the Custom Pack is never deleted, even when empty' do
    custom = Pack.custom
    sign_in_as_admin

    delete admin_pack_path(custom)

    assert_response :unprocessable_content
    assert_select '.errors li', /Custom/
    assert Pack.exists?(custom.id)
  end
end
