# frozen_string_literal: true

module Ratomic
  module Rack
    # Factory suitable for Ratomic::LocalPool.
    class WorkerFactory
      # @return [WorkerFactory] a shareable factory
      def self.new
        super.freeze
      end

      # Create one persistent Ractor worker.
      #
      # @return [Worker]
      def call
        Worker.new
      end
    end

    # Reusable Ractor-backed Rack application worker.
    class Worker
      def initialize
        @initialized = false
        # @type var application: untyped
        @ractor = Ractor.new do
          application = nil

          loop do
            command, reply, payload = Ractor.receive

            case command
            when :initialize
              application = payload
              reply.send(:ok)
            when :call
              begin
                response = application.call(payload.to_env)
                reply.send([:ok, response], move: true)
              rescue Exception => e # rubocop:disable Lint/RescueException
                error_data = [e.class.name.to_s, e.message.to_s, Array(e.backtrace)]
                reply.send([:error, error_data], move: true)
              end
            when :close
              break
            end
          end
        end
      end

      # Execute a request in the worker Ractor.
      #
      # @param application [#call] a Ractor-shareable Rack application
      # @param request [RequestEnvelope] an immutable request envelope
      # @return [Array] Rack response
      # @raise [Ratomic::Rack::Error] when the worker application raises
      def call(application, request)
        initialize_application(application) unless @initialized

        reply = Ractor::Port.new
        @ractor.send([:call, reply, request], move: true)
        receive_response(reply)
      ensure
        reply&.close unless reply&.closed?
      end

      # Stop the worker Ractor.
      #
      # @return [nil]
      def close
        @ractor.send([:close, nil, nil])
        @ractor.value
        nil
      rescue Ractor::ClosedError, Ractor::Error
        nil
      end

      private

      def initialize_application(application)
        raise ArgumentError, 'application must be Ractor-shareable' unless Ractor.shareable?(application)

        reply = Ractor::Port.new
        @ractor.send([:initialize, reply, application])
        reply.receive
        @initialized = true
      ensure
        reply&.close unless reply&.closed?
      end

      def receive_response(reply)
        result = reply.receive
        return result.fetch(1) if result.first == :ok

        error_class, message, backtrace = result.fetch(1)
        error = Error.new("#{error_class}: #{message}")
        error.set_backtrace(backtrace)
        raise error
      end
    end
  end
end
