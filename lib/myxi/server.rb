require 'socket'
require 'myxi/session'
module Myxi
  class Server

  def initialize(event_loop, options)
      @event_loop = event_loop
      port = (options[:port] || ENV['MYXI_PORT'] || ENV['PORT'] || 5005).to_i
      Myxi.logger.info "Running Myxi Web Socket Server on 0.0.0.0:#{port}"
      if ENV['SERVER_FD']
        @socket = TCPServer.for_fd(ENV['SERVER_FD'].to_i)
        Process.kill('TERM', Process.ppid)
      else
        @socket = TCPServer.open(options[:bind_address] || ENV['MYXI_BIND_ADDRESS'], port)
        ENV['SERVER_FD'] = @socket.to_i.to_s
      end
      @socket.close_on_exec = false
      monitor = event_loop.selector.register(@socket, :r)
      monitor.value = self
    end

    def handle_r
      # Incoming client connection
      client_socket = @socket.accept
      Session.new(@event_loop, client_socket)
    end

    def close
      @socket.close
      @event_loop.selector.deregister(@socket)
    end

  end
end
