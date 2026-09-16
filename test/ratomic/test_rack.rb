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
