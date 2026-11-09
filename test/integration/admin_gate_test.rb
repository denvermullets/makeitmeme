require 'test_helper'

class AdminGateTest < ActionDispatch::IntegrationTest
  test 'the admin home without sign-in redirects HTML to sign-in' do
    get admin_root_path
    assert_redirected_to admin_sign_in_path
  end

  test 'the admin home without sign-in returns 401 for JSON' do
    get admin_root_path, as: :json
    assert_response :unauthorized
  end

  test 'the sign-in page is reachable without signing in' do
    get admin_sign_in_path
    assert_response :success
    assert_select 'form input[type=password]'
  end

  test 'the correct password grants access to the admin home with its own layout' do
    sign_in_as_admin
    assert_redirected_to admin_root_path

    get admin_root_path
    assert_response :success
    assert_select 'body[data-layout=admin]'
  end

  test 'sign-in persists across later requests' do
    sign_in_as_admin
    2.times do
      get admin_root_path
      assert_response :success
    end
  end

  test 'a wrong password is rejected with an error and no access' do
    with_admin_password do
      post admin_sign_in_path, params: { password: 'nope' }
    end
    assert_response :unprocessable_entity
    assert_select '[role=alert]'

    get admin_root_path
    assert_redirected_to admin_sign_in_path
  end

  test 'every sign-in fails when the env var is unset' do
    with_admin_password(nil) do
      post admin_sign_in_path, params: { password: '' }
      assert_response :unprocessable_entity
      post admin_sign_in_path, params: { password: 'anything' }
      assert_response :unprocessable_entity
    end
    get admin_root_path
    assert_redirected_to admin_sign_in_path
  end

  test 'every sign-in fails when the env var is blank' do
    with_admin_password('') do
      post admin_sign_in_path, params: { password: '' }
      assert_response :unprocessable_entity
    end
    get admin_root_path
    assert_redirected_to admin_sign_in_path
  end

  test 'sign-out clears the flag' do
    sign_in_as_admin
    delete admin_sign_out_path
    assert_redirected_to admin_sign_in_path

    get admin_root_path
    assert_redirected_to admin_sign_in_path
  end

  test 'a Player with a Room cookie is not an Admin' do
    post rooms_path, params: { nickname: 'Ada' }
    get admin_root_path
    assert_redirected_to admin_sign_in_path
  end
end
