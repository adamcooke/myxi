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
      Myxi.logger.debug "[#{session.id}] \e[41;37mERROR\e[0m \e[31m#{e.class.to_s} #{e.message}\e[0m"
      e.backtrace { |br| Myxi.logger.debug "[#{session.id}] \e[41;37mERROR\e[0m #{br}" }
      session.send('InternalError', :error => e.class.to_s, :message => e.message)
    end

  end
end

require 'myxi/default_actions'
