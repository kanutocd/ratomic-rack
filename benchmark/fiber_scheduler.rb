# frozen_string_literal: true

require 'optparse'

# A deliberately small scheduler for this experiment only. It supports the
# `sleep` hook and is not intended for production I/O or Rack execution.
class TimerFiberScheduler
  def initialize
    @root = Fiber.current
    @waiting = {}
  end

  def fiber(&)
    fiber = Fiber.new(blocking: false, &)
    fiber.transfer
    fiber
  end

  def kernel_sleep(duration = nil) # rubocop:disable Naming/PredicateMethod
    @waiting[Fiber.current] = monotonic_time + (duration || 0)
    @root.transfer
    true
  end

  def block(_blocker, timeout = nil)
    return kernel_sleep(timeout) if timeout

    @root.transfer
  end

  def unblock(_blocker, _fiber)
    nil
  end

  def io_wait(*_arguments)
    raise NotImplementedError, 'TimerFiberScheduler only supports sleep'
  end

  def close
    return if @closed

    @closed = true

    until @waiting.empty?
      now = monotonic_time
      ready = @waiting.select { |_fiber, deadline| deadline <= now }.keys

      if ready.empty?
        sleep([@waiting.values.min - now, 0].max)
      else
        ready.each do |fiber|
          @waiting.delete(fiber)
          fiber.transfer if fiber.alive?
        end
      end
    end
  end

  alias scheduler_close close

  def fiber_interrupt(fiber, exception)
    fiber.raise(exception) if fiber.alive?
  end

  private

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

# Benchmark-only Ractor/Fiber scheduler comparison.
# rubocop:disable Style/OneClassPerFile
module FiberSchedulerExperiment
  module_function

  def execute(mode, fibers, sleep_seconds)
    completed = 0
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    if mode == :scheduler
      scheduler = TimerFiberScheduler.new
      Fiber.set_scheduler(scheduler)
      fibers.times do
        Fiber.schedule do
          sleep(sleep_seconds)
          completed += 1
        end
      end
      Fiber.set_scheduler(nil)
      scheduler.close
    else
      fibers.times do
        sleep(sleep_seconds)
        completed += 1
      end
    end

    [Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at, completed]
  end

  def run(mode:, fibers:, sleep_seconds:)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elapsed, completed = Ractor.new(mode, fibers, sleep_seconds) do |ractor_mode, fiber_count, duration|
      FiberSchedulerExperiment.execute(ractor_mode, fiber_count, duration)
    end.value

    {
      mode:,
      elapsed:,
      completed:,
      wall_elapsed: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    }
  end

  def benchmark(samples:, warmup:, fibers:, sleep_seconds:)
    modes = %i[without_scheduler with_scheduler]

    modes.each do |mode|
      warmup.times { run(mode: scheduler_mode(mode), fibers:, sleep_seconds:) }
      measurements = samples.times.map do
        run(mode: scheduler_mode(mode), fibers:, sleep_seconds:).fetch(:elapsed)
      end

      yield mode, measurements
    end
  end

  def scheduler_mode(mode)
    mode == :with_scheduler ? :scheduler : :baseline
  end
end
# rubocop:enable Style/OneClassPerFile

if $PROGRAM_NAME == __FILE__
  options = {
    fibers: 4,
    samples: 10,
    sleep_seconds: 0.005,
    warmup: 2
  }

  OptionParser.new do |parser|
    parser.banner = 'Usage: ruby benchmark/fiber_scheduler.rb [options]'
    parser.on('--fibers N', Integer, 'Fibers per Ractor (default: 4)') { |value| options[:fibers] = value }
    parser.on('--samples N', Integer, 'Measured samples (default: 10)') { |value| options[:samples] = value }
    parser.on('--sleep SECONDS', Float, 'Wait per operation (default: 0.005)') do |value|
      options[:sleep_seconds] = value
    end
    parser.on('--warmup N', Integer, 'Warmup samples (default: 2)') { |value| options[:warmup] = value }
  end.parse!

  puts "Ruby: #{RUBY_DESCRIPTION}"
  puts "Configuration: fibers=#{options[:fibers]}, sleep=#{options[:sleep_seconds]}s, " \
       "warmup=#{options[:warmup]}, samples=#{options[:samples]}"
  puts
  puts 'mode                      mean_ms       min_ms       max_ms'

  FiberSchedulerExperiment.benchmark(**options) do |mode, measurements|
    milliseconds = measurements.map { |measurement| measurement * 1000 }
    puts format(
      '%<mode>-20s %<mean>.3f %<min>.3f %<max>.3f',
      mode:,
      mean: milliseconds.sum / milliseconds.length,
      min: milliseconds.min,
      max: milliseconds.max
    )
  end
end
