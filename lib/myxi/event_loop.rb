require 'nio'
require 'timers'
require 'myxi/server'

module Myxi
  class EventLoop
    attr_reader :selector, :timers, :options, :sessions

    def initialize(options = {})
      @options = options
      @selector = NIO::Selector.new
      @timers = Timers::Group.new
      @sessions = []
    end

    def wakeup
      @selector.wakeup
    end

    def run
      Myxi::Exchange.declare_all
      @server = Server.new(self, options)

      unless options[:touch_interval] == 0
        @timers.every(options[:touch_interval] || 60) do
          @sessions.each(&:touch)
        end
      end

      Signal.trap("TERM") do
        if @options[:shutdown_time]
          @timers.after(0) do
            Myxi.logger.info("Received TERM signal, beginning #{@options[:shutdown_time]} second shutdown.")
          end
          @server.close

          @timers.every(1) do
            @shutdown_timer ||= 0
            @sessions.each do |session|
              if session.hash % @options[:shutdown_time] == @shutdown_timer % @options[:shutdown_time]
                session.close
              end
            end
            @shutdown_timer += 1

            if @sessions.size == 0
              Myxi.logger.info("All clients disconnected. Shutdown complete.")
              Process.exit(0)
            end
          end
          wakeup
        else
          @timers.after(0) do
            Myxi.logger.info("Received TERM signal, shutting down immediately")
              Process.exit(0)
          end
        end
      end

      loop do
        selector.select(@timers.wait_interval) do |monitor|
          begin
            monitor.value.handle_r if monitor.readable?
            monitor.value.handle_w if monitor.writeable?
          rescue => e
            # Try to recover wherever possible
            if monitor && monitor.value
              if monitor.value == @server
                raise
              else
                monitor.value.close rescue nil
              end
            end
            begin
              Myxi.logger.info(e.class.to_s + ' ' + e.message.to_s)
              e.backtrace.each do |line|
                Myxi.logger.info('  ' + line)
              end
            rescue
            end
          end
        end
        @timers.fire
      end

    end

  end
end
