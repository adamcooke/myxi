require 'websocket'
require 'json'
require 'myxi/exchange'
require 'myxi/eventable_socket'

module Myxi
  class Session < EventableSocket

    def initialize(event_loop, client_socket)
      @id  = SecureRandom.hex(8)
      @closure_callbacks = []
      @data = {}

      @handshake = WebSocket::Handshake::Server.new
      @state = :handshake
      super
      @event_loop.sessions << self

    end

    attr_reader :id
    #attr_accessor :queue
    attr_accessor :auth_object
    attr_accessor :tag

    def remote_ip
      if xff = @handshake.headers['x-forwarded-for']
        xff.to_s.split(/\s+/)[0]
      else
        @socket.peeraddr(false)[3]
      end
    end

    def on_connect
      Myxi.logger.debug "[#{id}] Connection opened"
      send_text_data({:event => 'Welcome', :payload => {:id => id}}.to_json)
      begin
        @queue = Myxi.channel.queue("", :exclusive => true)
      rescue NoMethodError
        # This exception may be raised when something goes very wrong with the RabbitMQ connection
        # Unfortunately the only practical solution is to restart the client
        Process.exit(1)
      end
      @queue.subscribe do |delivery_info, properties, body|
        if hash = JSON.parse(body) rescue nil
          hash['mq'] = {'e' => delivery_info.exchange, 'rk' => delivery_info.routing_key}
          payload = hash.to_json.force_encoding('UTF-8')
          Myxi.logger.debug "[#{id}] \e[45;37mEVENT\e[0m \e[35m#{payload}\e[0m (to #{delivery_info.exchange}/#{delivery_info.routing_key})"
          send_text_data(payload)
        end
      end
    end

    def handle_r
      case @state
      when :handshake
        @handshake << @socket.readpartial(1048576)
        if @handshake.finished?
          write(@handshake.to_s)
          if @handshake.valid?
            on_connect
            @state = :established
            @frame_handler = WebSocket::Frame::Incoming::Server.new(version: @handshake.version)
          else
            close_after_write
          end
        end
      when :established
        @frame_handler << @socket.readpartial(1048576)
        while frame = @frame_handler.next
          msg = frame.data
          json = JSON.parse(msg) rescue nil
          if json.is_a?(Hash)
            tag = json['tag'] || nil
            payload = json['payload'] || {}
            Myxi.logger.debug "[#{id}] \e[43;37mACTION\e[0m \e[33m#{json}\e[0m"
            if action = Myxi::Action::ACTIONS[json['action'].to_s.to_sym]
              action.execute(self, payload)
            else
              send_text_data({:event => 'Error', :tag => tag, :payload => {:error => 'InvalidAction'}}.to_json)
            end
          else
            send_text_data({:event => 'Error', :payload => {:error => 'InvalidJSON'}}.to_json)
          end
        end
      end
    rescue EOFError, Errno::ECONNRESET, IOError
      close
    end

    def [](name)
      @data[name.to_sym]
    end

    def []=(name, value)
      Myxi.logger.debug "[#{id}] Stored '#{name}' with '#{value}'"
      @data[name.to_sym] = value
    end

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
      payload = {:event => name, :tag => tag, :payload => payload}.to_json.force_encoding('UTF-8')
      send_text_data(payload)
      Myxi.logger.debug "[#{id}] \e[46;37mMESSAGE\e[0m \e[36m#{payload}\e[0m"
    end

    #
    # Subscribe this session to receive items for the given exchange & routing key
    #
    def subscribe(exchange_name, routing_key)
      if exchange = Myxi::Exchange::EXCHANGES[exchange_name.to_sym]
        if exchange.can_subscribe?(routing_key, self.auth_object)
          subscriptions[exchange_name.to_s] ||= []
          if subscriptions[exchange_name.to_s].include?(routing_key.to_s)
            send('Error', :error => 'AlreadySubscribed', :exchange => exchange_name, :routing_key => routing_key)
          else
            @queue.bind(exchange.exchange_name.to_s, :routing_key => routing_key.to_s)
            subscriptions[exchange_name.to_s] << routing_key.to_s
            Myxi.logger.debug "[#{id}] \e[42;37mSUBSCRIBED\e[0m \e[32m#{exchange_name} / #{routing_key}\e[0m"
            send('Subscribed', :exchange => exchange_name, :routing_key => routing_key)
          end
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
    def unsubscribe(exchange_name, routing_key, auto = false)
      @queue.unbind(exchange_name.to_s, :routing_key => routing_key.to_s)
      if subscriptions[exchange_name.to_s]
        subscriptions[exchange_name.to_s].delete(routing_key.to_s)
      end
      Myxi.logger.debug "[#{id}] \e[42;37mUNSUBSCRIBED\e[0m \e[32m#{exchange_name} / #{routing_key}\e[0m"
      send('Unsubscribed', :exchange_name => exchange_name, :routing_key => routing_key, :auto => auto)
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

    #
    # Called by the server every so often whenever this session is active. This
    # should verify that subscriptions are still valid etc...
    #
    def touch
      subscriptions.each do |exchange_name, routing_keys|
        if exchange = Myxi::Exchange::EXCHANGES[exchange_name.to_sym]
          routing_keys.each do |routing_key|
            unless exchange.can_subscribe?(routing_key, self.auth_object)
              Myxi.logger.info "[#{id}] Session is not longer allowed to subscibe to #{exchange_name}/#{routing_key}"
              unsubscribe(exchange_name, routing_key, true)
            end
          end
        end
      end
    end

    #
    # Called when the connection for this session is closed
    #
    def close
      Myxi.logger.debug "[#{id}] Session closed"
      @event_loop.sessions.delete(self)
      @queue.delete if @queue
      while callback = @closure_callbacks.shift
        callback.call(self)
      end
      super
    end

    #
    # Adds a callback to be executed when this session closes
    #
    def on_close(&block)
      @closure_callbacks << block
    end

    def send_text_data(data)
      sender = WebSocket::Frame::Outgoing::Server.new(version: @handshake.version, data: data, type: :text)
      write(sender.to_s)
    end

  end
end
