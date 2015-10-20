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
      @block.call(session, payload)
    end

  end
end

require 'myxi/default_actions'
