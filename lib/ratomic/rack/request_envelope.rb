# frozen_string_literal: true

module Ratomic
  module Rack
    # Immutable, explicitly selected request data that can cross a Ractor
    # boundary. It is converted back to a fresh Rack environment in the
    # worker Ractor.
    class RequestEnvelope
      HEADER_KEYS = %w[CONTENT_LENGTH CONTENT_TYPE].freeze
      SELECTED_ENV_KEYS = %w[
        HTTPS
        REMOTE_ADDR
        REMOTE_PORT
        SERVER_NAME
        SERVER_PORT
        SERVER_PROTOCOL
        rack.multiprocess
        rack.multithread
        rack.run_once
        rack.url_scheme
        rack.version
      ].freeze

      attr_reader :method, :path, :query_string, :headers, :body, :env_values

      # Build an envelope from the supported subset of a Rack environment.
      #
      # @param env [Hash] Rack environment
      # @return [RequestEnvelope]
      # @raise [ArgumentError] if a required or unsupported value is present
      def self.from_env(env)
        new(env)
      end

      def initialize(env)
        raise ArgumentError, 'env must be a Hash' unless env.is_a?(Hash)

        @method = immutable_string(required_string(env, 'REQUEST_METHOD'))
        @path = immutable_string(required_string(env, 'PATH_INFO'))
        @query_string = immutable_string(optional_string(env, 'QUERY_STRING'))
        @headers = immutable_string_hash(extract_headers(env))
        @body = immutable_string(extract_body(env))
        @env_values = immutable_values(extract_env_values(env))
        freeze
      end

      # Reconstruct a fresh Rack environment for the application Ractor.
      #
      # @return [Hash]
      def to_env
        env = duplicate_values(@env_values)
        env['REQUEST_METHOD'] = @method.dup
        env['PATH_INFO'] = @path.dup
        env['QUERY_STRING'] = @query_string.dup
        @headers.each { |key, value| env[key.dup] = value.dup }
        env['rack.input'] = @body.dup
        env
      end

      private

      def required_string(env, key)
        value = env.fetch(key)
        return value.dup if value.is_a?(String)

        raise ArgumentError, "#{key} must be a String"
      end

      def optional_string(env, key)
        value = env.fetch(key, '')
        return value.dup if value.is_a?(String)

        raise ArgumentError, "#{key} must be a String"
      end

      def extract_headers(env)
        headers = {} # : Hash[untyped, untyped]
        env.each do |key, value|
          next unless key.is_a?(String) && (key.start_with?('HTTP_') || HEADER_KEYS.include?(key))
          raise ArgumentError, "#{key} must be a String" unless value.is_a?(String)

          headers[key] = value.dup
        end
        headers
      end

      def extract_body(env)
        value = env.fetch('rack.input', '')
        return value.dup if value.is_a?(String)
        return ''.dup if value.nil?

        raise ArgumentError, 'rack.input must be a String in this phase'
      end

      def extract_env_values(env)
        values = {} # : Hash[String, untyped]
        SELECTED_ENV_KEYS.each do |key|
          values[key] = copy_value(env[key]) if env.key?(key)
        end
        values
      end

      def copy_value(value)
        case value
        when String
          value.dup.freeze
        when Array
          value.map { |item| copy_value(item) }.freeze
        when Integer, TrueClass, FalseClass, NilClass
          value
        else
          raise ArgumentError, 'selected Rack environment values must be immutable scalars'
        end
      end

      def immutable_string(value)
        raise ArgumentError, 'request values must be Strings' unless value.is_a?(String)

        value.dup.freeze
      end

      def immutable_string_hash(values)
        result = {} # : Hash[String, String]
        values.each do |key, value|
          result[key.to_s.dup.freeze] = immutable_string(value)
        end.freeze
        result
      end

      def immutable_values(values)
        result = {} # : Hash[String, untyped]
        values.each do |key, value|
          result[key] = value
        end
        result.freeze
      end

      def duplicate_values(values)
        result = {} # : Hash[String, untyped]
        values.each do |key, value|
          result[key] = case value
                        when String then value.dup
                        when Array then value.map(&:dup)
                        else value
                        end
        end
        result
      end
    end
  end
end
