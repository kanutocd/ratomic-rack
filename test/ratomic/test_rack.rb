# frozen_string_literal: true

require 'test_helper'

module Ratomic
  class TestRack < Minitest::Test
    class Application
      def self.call(env)
        raise 'application failure' if env['PATH_INFO'] == '/error'

        [200, { 'content-type' => 'text/plain' }, [env.fetch('PATH_INFO')]]
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
      response = @handler.call('PATH_INFO' => '/hello')

      assert_equal [200, { 'content-type' => 'text/plain' }, ['/hello']], response
    end

    def test_worker_is_reused_after_an_application_error
      error = assert_raises(Rack::Error) do
        @handler.call('PATH_INFO' => '/error')
      end

      assert_match(/application failure/, error.message)
      assert_equal [200, { 'content-type' => 'text/plain' }, ['/again']], @handler.call('PATH_INFO' => '/again')
    end

    def test_handler_rejects_a_non_shareable_application
      assert_raises(ArgumentError) do
        Rack::Handler.new(->(_env) { [] }, pool: @pool)
      end
    end

    def test_handler_requires_a_worker_pool
      pool = ::Ratomic::LocalPool.new(size: 1, factory: Ratomic::Rack::TestResourceFactory.new)

      error = assert_raises(ArgumentError) do
        Rack::Handler.new(Application, pool: pool).call('PATH_INFO' => '/hello')
      end

      assert_match(/Worker instances/, error.message)
    ensure
      pool&.close
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
