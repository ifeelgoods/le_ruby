require 'socket'
require 'openssl'
require 'thread'
require 'uri'

module Le
  module Host
    class HTTP
      include Le::Host::InstanceMethods
      attr_accessor :token, :queue, :started, :thread, :conn, :local

      def initialize(token, local)
        @logger_console = Logger.new("log/#{Rails.env}.log")
        @token = token
        @local = local
        @queue = Queue.new
        @started = false
        @thread = nil
      end

      def write(message)
        if @local then
          @logger_console.add(Logger::Severity::UNKNOWN,message)
        end

        @queue << "#{@token}#{message}\n"

        if @started then
          check_async_thread
        else
          start_async_thread
        end
      end

      def start_async_thread
        @thread = Thread.new{run()}
        @logger_console.add(Logger::Severity::UNKNOWN,"LE: Asynchronous socket writer started")
        @started = true
      end

      def check_async_thread
        if not @thread.alive?
          @thread = Thread.new{run()}
          @logger_console.add(Logger::Severity::UNKNOWN,"LE: Asyncrhonous socket writer restarted")
        end
      end

      def close
        @logger_console.add(Logger::Severity::UNKNOWN,"LE: Closing asynchronous socket writer")

        @started = false
      end

      def openConnection
        @logger_console.add(Logger::Severity::UNKNOWN,"LE: Reopening connection to Logentries API server")

        @conn = TCPSocket.new('api.logentries.com', 10000)
        @logger_console.add(Logger::Severity::UNKNOWN,"LE: Connection established")

      end

      def reopenConnection
        closeConnection
        root_delay = 0.1
        while true
          begin
            openConnection
            break
          rescue TimeoutError, Errno::EHOSTUNREACH, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, EOFError => e
            @logger_console.add(Logger::Severity::UNKNOWN,"LE: Unable to connect to Logentries")
          end
          root_delay *= 2
          if root_delay >= 10 then
            root_delay = 10
          end
          wait_for = (root_delay + rand(root_delay)).to_i
          @logger_console.add(Logger::Severity::UNKNOWN,"LE: Waiting for " + wait_for.to_s + "ms")
          sleep(wait_for)
        end
      end

      def closeConnection
        if @conn != nil
          @conn.sysclose
          @conn = nil
        end
      end

      def run
        reopenConnection

        while true
          data = @queue.pop
          while true
            begin
              @conn.write(data)
            rescue TimeoutError, Errno::EHOSTUNREACH, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEOUT, EOFError => e
              reopenConnection
              next
            end
            break
          end
        end
        @logger_console.add(Logger::Severity::UNKNOWN,"LE: Closing Asyncrhonous socket writer")
        closeConnection
      end
    end
  end
end
