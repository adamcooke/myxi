require 'myxi/environment'

module Myxi
  class Action

    ACTIONS = {}

    def self.add(name, &block)
      ACTIONS[name.to_sym] = self.new(name, &block)
    end

    def initialize(name, &block)
      @name = name
      @block = block
    end

    def execute(session, payload = {})
      environment = Environment.new(session, payload)
      environment.instance_exec(session, payload, &@block)
    rescue Environment::Error => e
      session.send('Error', :error => e.class.to_s.split('::').last)
    rescue => e
      session.send('InternalError', :error => e.class.to_s, :message => e.message)
    end

  end
end

require 'myxi/default_actions'
