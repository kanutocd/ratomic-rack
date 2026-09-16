# frozen_string_literal: true

require 'net/http'
require 'puma'
require 'test_helper'

module Ratomic
  class TestPumaRack < Minitest::Test
    class Application
      def self.call(env)
        body = env.fetch('rack.input').read
        response = [env.fetch('REQUEST_METHOD'), env.fetch('PATH_INFO'), env.fetch('QUERY_STRING'), body].join('|')

        [200, { 'content-type' => 'text/plain' }, [response]]
      end
    end

    def setup
      @pool = ::Ratomic::LocalPool.new(size: 2, factory: Rack::WorkerFactory.new)
      @handler = Rack::Handler.new(Application, pool: @pool)
      @server = Puma::Server.new(@handler, Puma::Events.new, min_threads: 2, max_threads: 4)
      @server.add_tcp_listener('127.0.0.1', 0)
      @port = @server.binder.connected_ports.first
      @server.run
    end

    def teardown
      @server&.stop(true)
      @handler&.close
    end

    def test_real_puma_server_dispatches_an_http_request
      response = request('/hello?name=world', body: 'request body')

      assert_equal '200', response.code
      assert_equal 'GET|/hello|name=world|request body', response.body
      assert_equal 'text/plain', response['content-type']
    end

    def test_concurrent_http_requests_are_served_without_losing_responses
      requests = 8.times.map do |index|
        Thread.new do
          response = request("/concurrent/#{index}", body: "body-#{index}")
          [response.code, response.body]
        end
      end.map(&:value)

      assert_equal 8, requests.size
      assert(requests.all? { |code, _body| code == '200' })
      assert_equal 8, requests.map(&:last).uniq.size
      assert_includes requests.map(&:last), 'GET|/concurrent/3||body-3'
    end

    private

    def request(path, body:)
      Net::HTTP.start('127.0.0.1', @port) do |http|
        request = Net::HTTP::Get.new(path)
        request.body = body
        http.request(request)
      end
    end
  end
end
