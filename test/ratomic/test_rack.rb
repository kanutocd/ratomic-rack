# frozen_string_literal: true

require 'test_helper'

module Ratomic
  class TestRack < Minitest::Test
    class Application
      def self.call(env)
        raise 'application failure' if env['PATH_INFO'] == '/error'

        [
          200,
          {
            'x-request-method' => env.fetch('REQUEST_METHOD'),
            'x-path' => env.fetch('PATH_INFO'),
            'x-query' => env.fetch('QUERY_STRING'),
            'x-request-id' => env.fetch('HTTP_X_REQUEST_ID', ''),
            'x-server-name' => env.fetch('SERVER_NAME', ''),
            'x-server-port' => env.fetch('SERVER_PORT', ''),
            'x-url-scheme' => env.fetch('rack.url_scheme', ''),
            'x-rack-version' => env.fetch('rack.version', []).join('.'),
            'x-multithread' => env.fetch('rack.multithread', false).to_s
          },
          [env.fetch('rack.input')]
        ]
      end
    end

    class StringBodyApplication
      def self.call(_env)
        [201, { 'x-body-type' => 'string' }, 'string body']
      end
    end

    class EnumerableBody
      def each
        yield 'first'
        yield 'second'
      end
    end

    class EnumerableBodyApplication
      def self.call(_env)
        [202, { 'x-body-type' => 'enumerable' }, EnumerableBody.new]
      end
    end

    class CloseableBody
      def initialize(port)
        @port = port
      end

      def each
        yield 'closeable body'
      end

      def close
        @port.send(:closed)
      end
    end

    class CloseableBodyApplication
      def initialize(port)
        @port = port
        freeze
      end

      def call(_env)
        [203, { 'x-body-type' => 'closeable' }, CloseableBody.new(@port)]
      end
    end

    def setup
      @pool = ::Ratomic::LocalPool.new(size: 1, factory: Rack::WorkerFactory.new)
      @handler = Rack::Handler.new(Application, pool: @pool)
    end

    def teardown
      @handler.close
    end

    def test_that_it_has_a_version_number
      refute_nil Rack::VERSION
    end

    def test_handler_dispatches_a_request_to_a_ractor_worker
      response = @handler.call(
        'REQUEST_METHOD' => 'POST',
        'PATH_INFO' => '/hello',
        'QUERY_STRING' => 'page=2&sort=name',
        'HTTP_X_REQUEST_ID' => 'request-123',
        'SERVER_NAME' => 'example.test',
        'SERVER_PORT' => '443',
        'rack.url_scheme' => 'https',
        'rack.version' => [3, 0],
        'rack.multithread' => true,
        'rack.input' => 'request body'
      )

      assert_equal 200, response[0]
      assert_equal 'POST', response[1]['x-request-method']
      assert_equal '/hello', response[1]['x-path']
      assert_equal 'page=2&sort=name', response[1]['x-query']
      assert_equal 'request-123', response[1]['x-request-id']
      assert_equal 'example.test', response[1]['x-server-name']
      assert_equal '443', response[1]['x-server-port']
      assert_equal 'https', response[1]['x-url-scheme']
      assert_equal '3.0', response[1]['x-rack-version']
      assert_equal 'true', response[1]['x-multithread']
      assert_equal ['request body'], response[2]
    end

    def test_handler_preserves_status_and_headers
      response = @handler.call(request_env('/headers').merge('HTTP_X_REQUEST_ID' => 'request-123'))

      assert_equal 200, response[0]
      assert_equal 'request-123', response[1]['x-request-id']
    end

    def test_string_response_body_is_materialized_as_an_array
      with_handler(StringBodyApplication) do |handler|
        response = handler.call(request_env('/string'))

        assert_equal 201, response[0]
        assert_equal ['string body'], response[2]
      end
    end

    def test_array_response_body_is_preserved
      response = @handler.call(request_env('/array').merge('rack.input' => 'array body'))

      assert_equal ['array body'], response[2]
    end

    def test_enumerable_response_body_is_materialized
      with_handler(EnumerableBodyApplication) do |handler|
        response = handler.call(request_env('/enumerable'))

        assert_equal 202, response[0]
        assert_equal %w[first second], response[2]
      end
    end

    def test_closeable_response_body_is_closed_before_returning
      port = Ractor::Port.new

      with_handler(CloseableBodyApplication.new(port)) do |handler|
        response = handler.call(request_env('/closeable'))

        assert_equal 203, response[0]
        assert_equal ['closeable body'], response[2]
        assert_equal :closed, port.receive
      end
    ensure
      port&.close unless port&.closed?
    end

    def test_worker_is_reused_after_an_application_error
      error = assert_raises(Rack::Error) do
        @handler.call(request_env('/error'))
      end

      assert_match(/application failure/, error.message)
      assert_equal 200, @handler.call(request_env('/again')).first
    end

    def test_handler_rejects_a_non_shareable_application
      assert_raises(ArgumentError) do
        Rack::Handler.new(->(_env) { [] }, pool: @pool)
      end
    end

    def test_handler_requires_a_worker_pool
      pool = ::Ratomic::LocalPool.new(size: 1, factory: Ratomic::Rack::TestResourceFactory.new)

      error = assert_raises(ArgumentError) do
        Rack::Handler.new(Application, pool: pool).call(request_env('/hello'))
      end

      assert_match(/Worker instances/, error.message)
    ensure
      pool&.close
    end

    def test_handler_rejects_a_non_string_rack_input
      assert_raises(ArgumentError) do
        @handler.call(request_env('/hello').merge('rack.input' => Object.new))
      end
    end

    private

    def request_env(path)
      { 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => path }
    end

    def with_handler(application)
      pool = ::Ratomic::LocalPool.new(size: 1, factory: Rack::WorkerFactory.new)
      handler = Rack::Handler.new(application, pool: pool)
      yield handler
    ensure
      handler&.close
    end
  end

  module Rack
    class TestResourceFactory
      def self.new
        super.freeze
      end

      def call
        Object.new
      end
    end
  end
end
