require 'json'
require 'myxi/exchange'

module Myxi
  class Session

    def initialize(ws)
      @ws = ws
      @id  = SecureRandom.hex(8)
    end

    attr_reader :id
    attr_reader :ws
    attr_accessor :queue
    attr_accessor :auth_object
    attr_accessor :tag

    #
    # Keep track of all subscriptions
    #
    def subscriptions
      @subscriptions ||= {}
    end

    #
    # Send an event back to the client on this session
    #
    def send(name, payload = {})
      ws.send({:event => name, :tag => tag, :payload => payload}.to_json)
    end

    #
    # Subscribe this session to receive items for the given exchange & routing key
    #
    def subscribe(exchange_name, routing_key)
      if exchange = Myxi::Exchange::EXCHANGES[exchange_name.to_sym]
        if exchange.can_subscribe?(routing_key, self.auth_object)
          queue.bind(exchange.exchange_name.to_s, :routing_key => routing_key.to_s)
          subscriptions[exchange_name.to_s] ||= []
          subscriptions[exchange_name.to_s] << routing_key.to_s
          puts "[#{id}] Subscribed to #{exchange_name} / #{routing_key}"
          send('Subscribed', :exchange => exchange_name, :routing_key => routing_key)
        else
          send('Error', :error => 'SubscriptionDenied', :exchange => exchange_name, :routing_key => routing_key)
        end
      else
        send('Error', :error => 'InvalidExchange', :exchange => exchange_name)
      end
    end

    #
    # Unsubscribe this session from the given exchange name and routing key
    #
    def unsubscribe(exchange_name, routing_key)
      queue.unbind(exchange_name.to_s, :routing_key => routing_key.to_s)
      if subscriptions[exchange_name.to_s]
        subscriptions[exchange_name.to_s].delete(routing_key.to_s)
      end
      send('Unsubscribed', :exchange_name => exchange_name, :routing_key => routing_key)
    end

    #
    # Unscubribe all for an exchange
    #
    def unsubscribe_all_for_exchange(exchange_name)
      if array = self.subscriptions[exchange_name.to_s]
        array.dup.each do |routing_key|
          self.unsubscribe(exchange_name.to_s, routing_key)
        end
      end
    end

    #
    # Unsubscribe all
    #
    def unsubscribe_all
      self.subscriptions.keys.each do |exchange_name|
        self.unsubscribe_all_for_exchange(exchange_name)
      end
    end

  end
end
