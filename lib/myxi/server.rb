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

    def sessions
      @sessions ||= []
    end

    def run
      Myxi::Exchange.declare_all
      port = (options[:port] || ENV['MYXI_PORT'] || ENV['PORT'] || 5005).to_i
      Myxi.logger.info "Running Myxi Web Socket Server on 0.0.0.0:#{port}"

      if ENV['SERVER_FD']
        @server = TCPServer.for_fd(ENV['SERVER_FD'].to_i)
        Process.kill('TERM', Process.ppid)
      else
        @server = TCPServer.open(options[:bind_address] || ENV['MYXI_BIND_ADDRESS'], port)
        ENV['SERVER_FD'] = @server.to_i.to_s
      end
      @server.autoclose = false
      @server.close_on_exec = false

      EM.run do
        wss = EM::WebSocket.run(:socket => @server) do |ws|
          sessions << session = Session.new(self, ws)

          ws.onopen do |handshake|
            case handshake.path
            when /\A\/pushwss/
              Myxi.logger.debug "[#{session.id}] Connection opened"
              ws.send({:event => 'Welcome', :payload => {:id => session.id}}.to_json)

              session.queue = Myxi.channel.queue("", :exclusive => true)
              session.queue.subscribe do |delivery_info, properties, body|
                if hash = JSON.parse(body) rescue nil
                  payload = hash.to_json.force_encoding('UTF-8')
                  Myxi.logger.debug "[#{session.id}] \e[45;37mEVENT\e[0m \e[35m#{payload}\e[0m (to #{delivery_info.exchange}/#{delivery_info.routing_key})"
                  hash['mq'] = {'e' => delivery_info.exchange, 'rk' => delivery_info.routing_key}
                  ws.send(payload)
                end
              end
            else
              Myxi.logger.debug "[#{session.id}] Invalid path"
              ws.send({:event => 'Error', :payload => {:error => 'PathNotFound'}}.to_json)
              ws.close
            end
          end

          ws.onclose do
            session.close
            sessions.delete(session)
          end

          ws.onmessage do |msg|
            if ws.state == :connected
              json = JSON.parse(msg) rescue nil
              if json.is_a?(Hash)
                session.tag = json['tag'] || nil
                payload = json['payload'] || {}
                Myxi.logger.debug "[#{session.id}] \e[43;37mACTION\e[0m \e[33m#{json}\e[0m"
                if action = Myxi::Action::ACTIONS[json['action'].to_s.to_sym]
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

        unless options[:touch_interval] == 0
          EventMachine.add_periodic_timer(options[:touch_interval] || 60) do
            sessions.each(&:touch)
          end
        end

        Signal.trap("TERM") do
          if @options[:shutdown_time]
            EM.add_timer(0) do
              Myxi.logger.info("Received TERM signal, beginning #{@options[:shutdown_time]} second shutdown.")
            end
            EM.stop_server(wss)
            EventMachine.add_periodic_timer(1) do
              @shutdown_timer ||= 0
              sessions.each do |session|
                if session.hash % @options[:shutdown_time] == @shutdown_timer % @options[:shutdown_time]
                  session.ws.close
                end
              end
              @shutdown_timer += 1

              if sessions.size == 0
                Myxi.logger.info("All clients disconnected. Shutdown complete.")
                EM.stop
              end
            end
          else
            EM.add_timer(0) do
              Myxi.logger.info("Received TERM signal, shutting down immediately")
              EM.stop
            end
          end
        end ## End tap

      end

    end
  end
end


module EventMachine
  module WebSocket
    def self.run(options)
      host, port, socket = options.values_at(:host, :port, :socket)

      if socket
        EM.attach_server(socket, Connection, options) do |c|
          yield c
        end
      else
        EM.start_server(host, port, Connection, options) do |c|
          yield c
        end
      end
    end
  end
end
