module ApplicationCable
  # The WebSocket handshake carries the same HttpOnly cookie as REST calls,
  # so the connection is authenticated by the same JWT check. Origins are
  # restricted by config.action_cable.allowed_request_origins.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = AuthToken.user_from(cookies[AuthToken::COOKIE_NAME]) || reject_unauthorized_connection
    end
  end
end
