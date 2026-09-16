# frozen_string_literal: true

require 'test_helper'
require 'timeout'

module Ratomic
  class TestStress < Minitest::Test
    class Application
      def initialize(start_port: nil)
        @start_port = start_port
        freeze
      end

      def call(env)
        path = env.fetch('PATH_INFO')

        case path
        when '/application-error'
          raise 'application failure'
        when '/ractor-error'
          raise Ractor::Error, 'ractor failure'
        when '/blocked'
          release_port = Ractor::Port.new
          @start_port.send(release_port)
          release_port.receive
        end

        [200, { 'x-path' => path }, ["#{path}|#{env.fetch('rack.input').read}"]]
      end
    end

    def test_application_exception_does_not_poison_worker
      with_handler do |handler|
        error = assert_raises(Rack::Error) { handler.call(request_env('/application-error')) }

        assert_match(/application failure/, error.message)
        assert_equal ['/healthy|body'], handler.call(request_env('/healthy', body: 'body'))[2]
      end
    end

    def test_ractor_exception_is_reported_and_worker_remains_usable
      with_handler do |handler|
        error = assert_raises(Rack::Error) { handler.call(request_env('/ractor-error')) }

        assert_match(/Ractor::Error: ractor failure/, error.message)
        assert_equal ['/healthy|body'], handler.call(request_env('/healthy', body: 'body'))[2]
      end
    end

    def test_concurrent_requests_return_their_own_responses
      with_handler(size: 4) do |handler|
        requests = 16.times.map { |index| ["/request-#{index}", "body-#{index}"] }
        threads = requests.map do |path, body|
          Thread.new { handler.call(request_env(path, body: body))[2].first }
        end

        responses = Timeout.timeout(5) { threads.map(&:value) }

        assert_equal requests.map { |path, body| "#{path}|#{body}" }.sort, responses.sort
      end
    end

    def test_pool_exhaustion_times_out_without_poisoning_worker
      start_port = Ractor::Port.new
      with_handler(size: 1, timeout: 0.05, application: Application.new(start_port:)) do |handler|
        active = Thread.new { handler.call(request_env('/blocked')) }
        release_port = start_port.receive

        assert_instance_of Ractor::Port, release_port

        exhausted = Thread.new do
          handler.call(request_env('/waiting'))
        rescue Exception => e # rubocop:disable Lint/RescueException
          e
        end
        error = Timeout.timeout(2) { exhausted.value }

        refute_kind_of Array, error, 'pool exhaustion unexpectedly returned a response'
        assert_instance_of Ratomic::Error, error

        release_port.send(:release)

        assert_equal 200, Timeout.timeout(2) { active.value }.first
        assert_equal ['/healthy|body'], handler.call(request_env('/healthy', body: 'body'))[2]
      end
    ensure
      start_port&.close unless start_port&.closed?
    end

    def test_shutdown_during_activity_does_not_deadlock_or_lose_response
      start_port = Ractor::Port.new
      with_handler(size: 1, application: Application.new(start_port:)) do |handler|
        active = Thread.new { handler.call(request_env('/blocked', body: 'body')) }
        release_port = start_port.receive

        assert_instance_of Ractor::Port, release_port

        shutdown = Thread.new { handler.close }

        assert_nil Timeout.timeout(2) { shutdown.value }

        release_port.send(:release)
        response = Timeout.timeout(2) { active.value }

        assert_equal ['/blocked|body'], response[2]
        assert_raises(IOError) { handler.call(request_env('/after-shutdown')) }
      end
    ensure
      start_port&.close unless start_port&.closed?
    end

    def test_repeated_requests_do_not_leak_request_state
      with_handler do |handler|
        responses = 30.times.map do |index|
          path = "/repeat-#{index}"
          body = "body-#{index}"
          handler.call(request_env(path, body:))[2].first
        end

        assert_equal 30, responses.uniq.length
        assert_equal '/repeat-0|body-0', responses.first
        assert_equal '/repeat-29|body-29', responses.last
      end
    end

    private

    def request_env(path, body: '')
      { 'REQUEST_METHOD' => 'POST', 'PATH_INFO' => path, 'rack.input' => body }
    end

    def with_handler(size: 1, timeout: 1.0, application: Application.new)
      pool = ::Ratomic::LocalPool.new(size:, timeout:, factory: Rack::WorkerFactory.new)
      handler = Rack::Handler.new(application, pool:)
      yield handler
    ensure
      handler&.close
    end
  end
end
