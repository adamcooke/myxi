module Myxi
  class Environment

    class Error < StandardError; end
    class AuthRequired < Error; end

    def initialize(session, payload = {})
      @session, @payload = session, payload
    end

    attr_reader :session
    attr_reader :payload

    def auth_required!
      if session.auth_object.nil?
        raise AuthRequired, "Authentication is required for this action"
      end
    end

  end
end
