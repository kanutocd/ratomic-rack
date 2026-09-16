# frozen_string_literal: true

require 'json'
require 'net/http'
require 'optparse'
require 'puma'
require 'rbconfig'
require 'etc'
require 'fileutils'
require 'socket'
require 'timeout'

require_relative '../lib/ratomic/rack'
require_relative 'fiber_scheduler'

# Rack application used by the benchmark workloads.
class PumaBenchmarkApplication
  def initialize(workload:, cpu_iterations:, io_delay:, io_operations:, scheduler: false)
    @workload = workload
    @cpu_iterations = cpu_iterations
    @io_delay = io_delay
    @io_operations = io_operations
    @scheduler = scheduler
    freeze
  end

  def call(_env)
    case @workload
    when 'trivial'
      body = 'OK'
    when 'cpu'
      body = cpu_work.to_s
    when 'blocking_io'
      sleep(@io_delay)
      body = 'OK'
    when 'concurrent_io'
      mode = @scheduler ? :scheduler : :baseline
      FiberSchedulerExperiment.execute(mode, @io_operations, @io_delay)
      body = 'OK'
    else
      raise ArgumentError, "unknown workload: #{@workload}"
    end

    [200, { 'content-type' => 'text/plain', 'content-length' => body.bytesize.to_s }, [body]]
  end

  private

  def cpu_work
    value = 0
    @cpu_iterations.times { value = ((value * 1_664_525) + 1_013_904_223) & 0xffff_ffff }
    value
  end
end

# Puma benchmark runner for the baseline and Ratomic variants.
# rubocop:disable Style/OneClassPerFile, Metrics/ClassLength
class PumaWorkloadBenchmark
  MODES = %w[baseline ratomic ratomic_scheduler].freeze
  WORKLOADS = %w[trivial cpu blocking_io concurrent_io].freeze

  def initialize(options)
    @options = options
  end

  def run(output: $stdout)
    print_metadata(output)

    MODES.each do |mode|
      WORKLOADS.each do |workload|
        @options[:samples].times do |sample|
          record = benchmark_sample(mode:, workload:, sample:)
          output.puts(JSON.generate(record))
          output.flush
        end
      end
    end
  end

  private

  def benchmark_sample(mode:, workload:, sample:) # rubocop:disable Metrics/MethodLength
    server, handler, _port, startup_ms = start_server(mode, workload)
    begin
      warmup
      measurement = measure_requests
    ensure
      shutdown_started = monotonic_time
      server.stop(true)
      handler&.close
      shutdown_ms = elapsed_ms(shutdown_started)
    end

    {
      type: 'puma_ratomic_benchmark',
      mode:,
      workload:,
      sample:,
      configuration: configuration,
      startup_ms: startup_ms,
      shutdown_ms: shutdown_ms,
      requests_per_second: measurement[:requests_per_second],
      total_ms: measurement[:total_ms],
      error_rate: measurement[:error_rate],
      p50_ms: percentile(measurement[:latencies_ms], 0.50),
      p95_ms: percentile(measurement[:latencies_ms], 0.95),
      p99_ms: percentile(measurement[:latencies_ms], 0.99),
      latencies_ms: measurement[:latencies_ms],
      errors: measurement[:errors]
    }
  end

  def start_server(mode, workload) # rubocop:disable Metrics/MethodLength
    app = PumaBenchmarkApplication.new(
      workload:,
      cpu_iterations: @options[:cpu_iterations],
      io_delay: @options[:io_delay],
      io_operations: @options[:io_operations],
      scheduler: mode == 'ratomic_scheduler'
    )
    handler = nil

    if mode == 'baseline'
      rack_app = app
    else
      pool = Ratomic::LocalPool.new(size: @options[:pool_size], factory: Ratomic::Rack::WorkerFactory.new)
      handler = Ratomic::Rack::Handler.new(app, pool:)
      rack_app = handler
    end

    server = Puma::Server.new(
      rack_app,
      Puma::Events.new,
      min_threads: @options[:threads],
      max_threads: @options[:threads]
    )
    server.add_tcp_listener(@options[:host], 0)
    port = server.binder.connected_ports.first
    started = monotonic_time
    server.run
    wait_for_server(port)

    [server, handler, port, elapsed_ms(started)]
  rescue Exception # rubocop:disable Lint/RescueException
    handler&.close
    server&.stop(true)
    raise
  end

  def warmup
    issue_requests(@options[:warmup])
  end

  def measure_requests
    started = monotonic_time
    results = issue_requests(@options[:requests])
    total_ms = elapsed_ms(started)
    latencies = results.filter_map { |result| result[:latency_ms] }

    {
      total_ms:,
      requests_per_second: @options[:requests] / (total_ms / 1000.0),
      error_rate: (results.length - latencies.length).fdiv(results.length),
      latencies_ms: latencies,
      errors: results.filter_map { |result| result[:error] }
    }
  end

  def issue_requests(count)
    queue = Queue.new
    count.times { |index| queue << index }
    @options[:concurrency].times { queue << nil }
    results = Array.new(count)

    threads = @options[:concurrency].times.map do
      Thread.new do
        loop do
          index = queue.pop
          break unless index

          started = monotonic_time
          response = http_get
          results[index] = { latency_ms: elapsed_ms(started) } if response.is_a?(Net::HTTPSuccess)
          results[index] ||= { error: "HTTP #{response.code}" }
        rescue StandardError => e
          results[index] = { error: "#{e.class}: #{e.message}" }
        end
      end
    end
    threads.each(&:join)
    results
  end

  def http_get
    Net::HTTP.start(@options[:host], @current_port) do |http|
      http.get('/')
    end
  end

  def wait_for_server(port)
    @current_port = port
    Timeout.timeout(5) do
      loop do
        TCPSocket.new(@options[:host], port).close
        return
      rescue Errno::ECONNREFUSED
        sleep(0.01)
      end
    end
  end

  def configuration
    {
      ruby: RUBY_DESCRIPTION,
      ruby_engine: RUBY_ENGINE,
      puma: Puma::Const::PUMA_VERSION,
      ratomic: Ratomic::VERSION,
      os: RbConfig::CONFIG['host_os'],
      cpu_cores: Etc.nprocessors,
      puma_workers: 1,
      puma_threads: @options[:threads],
      ratomic_pool: @options[:pool_size],
      fiber_scheduler: 'TimerFiberScheduler only for ratomic_scheduler mode',
      request_count: @options[:requests],
      concurrency: @options[:concurrency],
      warmup: @options[:warmup],
      cpu_iterations: @options[:cpu_iterations],
      io_delay_seconds: @options[:io_delay],
      io_operations: @options[:io_operations]
    }
  end

  def print_metadata(output)
    output.puts JSON.generate(type: 'benchmark_metadata', configuration: configuration)
  end

  def percentile(values, fraction)
    return nil if values.empty?

    values.sort.fetch([(values.length * fraction).ceil - 1, 0].max)
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def elapsed_ms(started)
    (monotonic_time - started) * 1000
  end
end
# rubocop:enable Style/OneClassPerFile, Metrics/ClassLength

if $PROGRAM_NAME == __FILE__
  options = {
    concurrency: 4,
    cpu_iterations: 100_000,
    io_delay: 0.005,
    io_operations: 4,
    output: nil,
    pool_size: 4,
    requests: 40,
    samples: 3,
    threads: 4,
    warmup: 10,
    host: '127.0.0.1'
  }

  OptionParser.new do |parser|
    parser.banner = 'Usage: bundle exec ruby benchmark/puma_workloads.rb [options]'
    parser.on('--requests N', Integer) { |value| options[:requests] = value }
    parser.on('--concurrency N', Integer) { |value| options[:concurrency] = value }
    parser.on('--samples N', Integer) { |value| options[:samples] = value }
    parser.on('--warmup N', Integer) { |value| options[:warmup] = value }
    parser.on('--threads N', Integer) { |value| options[:threads] = value }
    parser.on('--pool-size N', Integer) { |value| options[:pool_size] = value }
    parser.on('--cpu-iterations N', Integer) { |value| options[:cpu_iterations] = value }
    parser.on('--io-delay SECONDS', Float) { |value| options[:io_delay] = value }
    parser.on('--io-operations N', Integer) { |value| options[:io_operations] = value }
    parser.on('--output PATH') { |value| options[:output] = value }
  end.parse!

  benchmark = PumaWorkloadBenchmark.new(options)
  if options[:output]
    FileUtils.mkdir_p(File.dirname(options[:output]))
    File.open(options[:output], 'w') { |file| benchmark.run(output: file) }
  else
    benchmark.run
  end
end
