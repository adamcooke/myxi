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

    def run
      Myxi::Exchange.declare_all
      port = (options[:port] || ENV['MYXI_PORT'] || ENV['PORT'] || 5005).to_i
      puts "Running Myxi Web Socket Server on 0.0.0.0:#{port}"
      EM.run do
        EM::WebSocket.run(:host => options[:bind_address] || ENV['MYXI_BIND_ADDRESS'] || '0.0.0.0', :port => port) do |ws|

          session = Session.new(ws)

          ws.onopen do |handshake|
            case handshake.path
            when /\A\/push\.ws/
              log "[#{session.id}] Connection opened"
              ws.send({:event => 'Welcome', :payload => {:id => session.id}}.to_json)

              session.queue = Myxi.channel.queue("", :exclusive => true)
              session.queue.subscribe do |delivery_info, properties, body|
                ws.send(body)
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
          end

          ws.onmessage do |msg|
            if ws.state == :connected
              if json = JSON.parse(msg) rescue nil
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
