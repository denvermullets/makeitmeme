module ApplicationCable
  # A connection is identified by the browser token in the signed cookie. There are no accounts;
  # a connection without a valid signed cookie is rejected.
  class Connection < ActionCable::Connection::Base
    identified_by :browser_token

    def connect
      self.browser_token = cookies.signed[:browser_token].presence || reject_unauthorized_connection
    end
  end
end
