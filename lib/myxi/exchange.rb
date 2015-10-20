module Myxi
  class Exchange

    EXCHANGES = {}

    attr_accessor :exchange_name
    attr_accessor :model_name
    attr_accessor :key_type

    def self.add(exchange_name, *args, &block)
      EXCHANGES[exchange_name.to_sym] = self.new(exchange_name, *args, &block)
    end

    def self.declare_all
      EXCHANGES.keys.each do |exch|
        Myxi.channel.direct(exch.to_s)
      end
    end

    def initialize(exchange_name, model_name = nil, &block)
      @exchange_name = exchange_name.to_sym
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

  end
end
