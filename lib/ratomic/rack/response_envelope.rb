# frozen_string_literal: true

module Ratomic
  module Rack
    # Transferable, materialized subset of a Rack response.
    class ResponseEnvelope
      attr_reader :status, :headers, :body

      # Normalize a Rack response before it crosses the Ractor boundary.
      #
      # Supported bodies are String, Array<String>, and Enumerable objects
      # yielding String chunks. Enumerable bodies are fully materialized and
      # closeable bodies are closed before the envelope is returned.
      #
      # @param response [Array] Rack response triple
      # @return [ResponseEnvelope]
      # @raise [ArgumentError] if the response is outside the supported subset
      def self.from_rack_response(response)
        new(response)
      end

      def initialize(response)
        raise ArgumentError, 'response must be a three-element Array' unless response.is_a?(Array) && response.size == 3
        raise ArgumentError, 'status must be an Integer' unless response[0].is_a?(Integer)

        @status = response[0]
        @headers = copy_headers(response[1])
        @body = materialize_body(response[2]).freeze
        freeze
      end

      # Return a fresh Rack response owned by the caller Ractor.
      #
      # @return [Array]
      def to_rack_response
        [@status, @headers.dup, @body.map(&:dup)]
      end

      private

      def materialize_body(body)
        return [body.dup.freeze] if body.is_a?(String)
        raise ArgumentError, 'response body must respond to #each' unless body.respond_to?(:each)

        chunks = [] # : Array[String]
        begin
          body.each do |chunk|
            raise ArgumentError, 'response body chunks must be Strings' unless chunk.is_a?(String)

            chunks << chunk.dup.freeze
          end
        ensure
          body.close if body.respond_to?(:close)
        end
        chunks
      end

      def copy_headers(headers)
        raise ArgumentError, 'response headers must be a Hash' unless headers.is_a?(Hash)

        copied = {} # : Hash[String, String]
        headers.each do |key, value|
          unless key.is_a?(String) && value.is_a?(String)
            raise ArgumentError, 'response header names and values must be Strings'
          end

          copied[key.dup.freeze] = value.dup.freeze
        end
        copied.freeze
      end
    end
  end
end
