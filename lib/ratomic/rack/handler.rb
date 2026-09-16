# frozen_string_literal: true

module Ratomic
  module Rack
    # Minimal Rack adapter that dispatches calls to reusable Ractor workers
    # checked out from an Ratomic::LocalPool.
    class Handler
      # @param application [#call] a Ractor-shareable Rack application
      # @param pool [#with] an Ratomic::LocalPool configured with WorkerFactory
      # @raise [ArgumentError] if the application is not Ractor-shareable
      def initialize(application, pool:)
        raise ArgumentError, 'application must be Ractor-shareable' unless Ractor.shareable?(application)
        unless pool.respond_to?(:with) && pool.respond_to?(:close)
          raise ArgumentError, 'pool must respond to #with and #close'
        end

        @application = application
        @lifecycle_mutex = Mutex.new
        @closed = false
        @pool = pool
      end

      # Dispatch one Rack request through a reusable worker.
      #
      # The request environment is moved to the worker and must therefore not
      # be used by the caller after this method returns. Only transferable Rack
      # environments and response values are supported in this phase.
      #
      # @param env [Hash] Rack environment
      # @return [Array] Rack response
      def call(env)
        @lifecycle_mutex.synchronize do
          raise IOError, 'handler is closed' if @closed
        end

        request = RequestEnvelope.from_env(env)

        @pool.with do |worker|
          raise ArgumentError, 'pool must yield Ratomic::Rack::Worker instances' unless worker.is_a?(Worker)

          worker.call(@application, request)
        end
      end

      # Close workers owned by the current Ractor through the configured pool.
      #
      # @return [nil]
      def close
        @lifecycle_mutex.synchronize { @closed = true }
        @pool.close
        nil
      end
    end
  end
end
