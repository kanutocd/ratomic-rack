# frozen_string_literal: true

require 'test_helper'

module Ratomic
  class TestEnvelopes < Minitest::Test
    class CloseableBody
      attr_reader :closed

      def initialize
        @closed = false
      end

      def each
        yield 'body'
      end

      def close
        @closed = true
      end
    end

    class InvalidBody
      def each
        yield Object.new
      end
    end

    class Readable
      def initialize(value)
        @value = value
      end

      def read
        @value
      end
    end

    def test_request_envelope_reconstructs_supported_values
      envelope = Rack::RequestEnvelope.from_env(
        'REQUEST_METHOD' => 'POST',
        'PATH_INFO' => '/items',
        'QUERY_STRING' => 'page=2',
        'HTTP_X_REQUEST_ID' => '123',
        'rack.input' => StringIO.new('body'),
        'rack.version' => [3, 0],
        'rack.multithread' => true
      )

      env = envelope.to_env

      assert_equal 'POST', envelope.method
      assert_equal '/items', envelope.path
      assert_equal 'page=2', envelope.query_string
      assert_equal({ 'HTTP_X_REQUEST_ID' => '123' }, envelope.headers)
      assert_equal 'body', envelope.body
      assert_equal 'body', env.fetch('rack.input').read
      assert_equal [3, 0], env.fetch('rack.version')
      assert env.fetch('rack.multithread')
    end

    def test_request_envelope_rejects_invalid_values
      assert_raises(ArgumentError) { Rack::RequestEnvelope.from_env(nil) }
      assert_raises(KeyError) { Rack::RequestEnvelope.from_env('PATH_INFO' => '/') }
      assert_raises(ArgumentError) { Rack::RequestEnvelope.from_env('REQUEST_METHOD' => 1, 'PATH_INFO' => '/') }
      assert_raises(ArgumentError) { Rack::RequestEnvelope.from_env('REQUEST_METHOD' => 'GET', 'PATH_INFO' => 1) }
      assert_raises(ArgumentError) do
        Rack::RequestEnvelope.from_env('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/', 'QUERY_STRING' => 1)
      end
      assert_raises(ArgumentError) do
        Rack::RequestEnvelope.from_env('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/', 'HTTP_X_TEST' => 1)
      end
      assert_raises(ArgumentError) do
        Rack::RequestEnvelope.from_env('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/',
                                       'rack.input' => Readable.new(Object.new))
      end
      assert_raises(ArgumentError) do
        Rack::RequestEnvelope.from_env('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/', 'rack.version' => Object.new)
      end
    end

    def test_request_envelope_supports_empty_and_nil_bodies
      empty = Rack::RequestEnvelope.from_env('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/')
      nil_body = Rack::RequestEnvelope.from_env('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/', 'rack.input' => nil)

      assert_equal '', empty.body
      assert_equal '', nil_body.body
    end

    def test_response_envelope_materializes_supported_bodies
      closeable = CloseableBody.new
      string = Rack::ResponseEnvelope.from_rack_response([201, { 'x-test' => 'yes' }, 'string'])
      array = Rack::ResponseEnvelope.from_rack_response([202, {}, %w[one two]])
      enumerable = Rack::ResponseEnvelope.from_rack_response([203, {}, closeable])

      assert_equal [201, { 'x-test' => 'yes' }, ['string']], string.to_rack_response
      assert_equal [202, {}, %w[one two]], array.to_rack_response
      assert_equal [203, {}, ['body']], enumerable.to_rack_response
      assert closeable.closed
    end

    def test_response_envelope_rejects_invalid_values
      assert_raises(ArgumentError) { Rack::ResponseEnvelope.from_rack_response([]) }
      assert_raises(ArgumentError) { Rack::ResponseEnvelope.from_rack_response(['200', {}, []]) }
      assert_raises(ArgumentError) { Rack::ResponseEnvelope.from_rack_response([200, [], []]) }
      assert_raises(ArgumentError) { Rack::ResponseEnvelope.from_rack_response([200, { 'x' => 1 }, []]) }
      assert_raises(ArgumentError) { Rack::ResponseEnvelope.from_rack_response([200, {}, Object.new]) }
      assert_raises(ArgumentError) { Rack::ResponseEnvelope.from_rack_response([200, {}, InvalidBody.new]) }
    end
  end
end
