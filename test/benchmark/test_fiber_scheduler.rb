# frozen_string_literal: true

require 'test_helper'
require 'open3'
require 'rbconfig'

class TestFiberSchedulerExperiment < Minitest::Test
  def test_benchmark_reports_both_ractor_variants
    stdout, _stderr, status = Open3.capture3(
      RbConfig.ruby,
      'benchmark/fiber_scheduler.rb',
      '--fibers', '2',
      '--sleep', '0.001',
      '--samples', '1',
      '--warmup', '0'
    )

    assert_predicate status, :success?
    assert_includes stdout, 'without_scheduler'
    assert_includes stdout, 'with_scheduler'
  end

  def test_benchmark_script_is_explicit_about_the_experimental_scope
    readme = File.read('benchmark/README.md')

    assert_includes readme, 'not a production scheduler'
    assert_match(/does\s+not establish a benefit/, readme)
  end
end
