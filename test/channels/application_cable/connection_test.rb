require 'test_helper'

module ApplicationCable
  class ConnectionTest < ActionCable::Connection::TestCase
    test 'connects identified by the browser token in the signed cookie' do
      cookies.signed[:browser_token] = 'tok-123'

      connect

      assert_equal 'tok-123', connection.browser_token
    end

    test 'rejects a connection without a cookie' do
      assert_reject_connection { connect }
    end

    test 'rejects a connection with a tampered cookie' do
      cookies[:browser_token] = 'forged'

      assert_reject_connection { connect }
    end
  end
end
