# frozen_string_literal: true

require 'simplecov'

SimpleCov.start do
  enable_coverage :branch
  minimum_coverage line: 90, branch: 80
  coverage_dir 'coverage'
  skip '/test/'
  skip '/bin/'
  skip 'version.rb'
end
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'ratomic/rack'

require 'minitest/autorun'
