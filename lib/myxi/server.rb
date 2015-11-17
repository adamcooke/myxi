require 'json'
require 'em-websocket'
require 'myxi'
require 'myxi/session'
require 'myxi/action'

module Myxi
  class Server

    attr_reader :options

    def initialize(options = {})
      @options = options
    end

    def log(message)
      if options[:debug]
        puts message
      end
    end

    def sessions
      @sessions ||= []
    end

    def monitor_sessions
      unless options[:touch_interval] == 0
        Thread.new do
          loop do
            sessions.each(&:touch)
            sleep options[:touch_interval] || 60
          end
        end
      end
    end

    def run
      Myxi::Exchange.declare_all
      port = (options[:port] || ENV['MYXI_PORT'] || ENV['PORT'] || 5005).to_i
      puts "Running Myxi Web Socket Server on 0.0.0.0:#{port}"
      monitor_sessions
      EM.run do
        EM::WebSocket.run(:host => options[:bind_address] || ENV['MYXI_BIND_ADDRESS'] || '0.0.0.0', :port => port) do |ws|

          sessions << session = Session.new(self, ws)

          ws.onopen do |handshake|
            case handshake.path
            when /\A\/pushwss/
              log "[#{session.id}] Connection opened"
              ws.send({:event => 'Welcome', :payload => {:id => session.id}}.to_json)

              session.queue = Myxi.channel.queue("", :exclusive => true)
              session.queue.subscribe do |delivery_info, properties, body|
                if hash = JSON.parse(body) rescue nil
                  hash['mq'] = {'e' => delivery_info.exchange, 'rk' => delivery_info.routing_key}
                  ws.send(hash.to_json.force_encoding('UTF-8'))
                end
              end
            else
              log "[#{session.id}] Invalid path"
              ws.send({:event => 'Error', :payload => {:error => 'PathNotFound'}}.to_json)
              ws.close
            end
          end

          ws.onclose do
            log "[#{session.id}] Disconnected"
            session.queue.delete if session.queue
            sessions.delete(session)
          end

          ws.onmessage do |msg|
            if ws.state == :connected
              json = JSON.parse(msg) rescue nil
              if json.is_a?(Hash)
                session.tag = json['tag'] || nil
                payload = json['payload'] || {}
                if action = Myxi::Action::ACTIONS[json['action'].to_sym]
                  action.execute(session, payload)
                else
                  ws.send({:event => 'Error', :tag => session.tag, :payload => {:error => 'InvalidAction'}}.to_json)
                end
              else
                ws.send({:event => 'Error', :payload => {:error => 'InvalidJSON'}}.to_json)
              end
            end
          end
        end
      end

    end
  end
end
