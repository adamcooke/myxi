module Myxi
  class EventableSocket
    def initialize(event_loop, socket)
      @event_loop = event_loop
      @socket = socket
      @monitor = @event_loop.selector.register(@socket, :r)
      @monitor.value = self
      @read_buffer = String.new.force_encoding('BINARY')
      @write_buffer = String.new.force_encoding('BINARY')
    end

    def handle_w
      bytes_sent = @socket.write_nonblock(@write_buffer)
      # Send as much data as possible
      if bytes_sent >= @write_buffer.bytesize
        @write_buffer = String.new.force_encoding('BINARY')
        @monitor.interests = :r
        close if @close_after_write
      else
        @write_buffer.slice!(0, bytes_sent)
      end
    rescue Errno::ECONNRESET, IOError
      close
    end

    def write(data)
      @event_loop.wakeup
      @write_buffer << data.force_encoding('BINARY')
      @monitor.interests = :rw
    end

    def close_after_write
      @close_after_write = true
      @monitor.interests = :w
    end

    def close
      @socket.close
      @event_loop.selector.deregister(@socket)
    end
  end
end
