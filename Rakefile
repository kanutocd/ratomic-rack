# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'minitest/test_task'
require 'rubocop/rake_task'
require 'rake/testtask'
require 'yard'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.warning = false
  t.test_files = FileList['test/**/test_*.rb']
end

RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ['--parallel']
end

YARD::Rake::YardocTask.new(:yard) do |task|
  task.files = ['lib/**/*.rb']
end

namespace :yard do
  desc 'Validate YARD documentation coverage'
  task :validate do
    require 'open3'

    stdout, stderr, status = Open3.capture3('bundle', 'exec', 'yard', 'stats')
    text = "#{stdout}\n#{stderr}"
    puts text
    abort('yard stats failed') unless status.success?

    match = text.match(/([0-9]+(?:\.[0-9]+)?)%\s+documented/)
    abort('Unable to determine YARD coverage') unless match

    coverage = match[1].to_f
    minimum = 95.0
    abort(format('YARD coverage %<coverage>.2f%% is below %<minimum>.2f%%', coverage:, minimum:)) if coverage < minimum

    puts format('YARD coverage %.2f%%', coverage)
  end
end

desc 'Validate curated RBS signatures'
task :steep_check do
  sh 'bundle exec steep check'
end

task default: %i[test rubocop steep_check yard yard:validate]

desc 'Run the complete quality gate'
task quality: %i[test rubocop steep_check yard:validate]
