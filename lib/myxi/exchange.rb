module Myxi
  class Exchange

    EXCHANGES = {}

    attr_accessor :exchange_name
    attr_accessor :exchange_type
    attr_accessor :exchange_durability
    attr_accessor :model_name
    attr_accessor :key_type

    def self.add(exchange_name, *args, &block)
      EXCHANGES[exchange_name.to_sym] = self.new(exchange_name, *args, &block)
    end

    def self.declare_all
      EXCHANGES.values.each do |exch|
        exch.declare
      end
    end

    def initialize(exchange_name, model_name = nil, exchange_type = 'direct', exchange_durability = false, &block)
      @exchange_name = exchange_name.to_sym
      @exchange_type = exchange_type.to_sym
      @exchange_durability = exchange_durability
      @model_name = model_name
      @permission_block = block
    end

    def has_model?
      !!@model_name
    end

    def model
      has_model? && model_name.constantize
    end

    def key_type
      @key_type || 'id'
    end

    def model_instance(id)
      has_model? ? model.where(key_type.to_sym => id.to_i).first : nil
    end

    def can_subscribe?(routing_key, user)
      if has_model?
        @permission_block.call(model_instance(routing_key), user)
      else
        @permission_block.call(routing_key, user)
      end
    end

    def declare
      Myxi.channel.send(@exchange_type, @exchange_name.to_s, durable: @exchange_durability)
    end
  end
end
