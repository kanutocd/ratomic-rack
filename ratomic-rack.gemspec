# frozen_string_literal: true

require_relative 'lib/ratomic/rack/version'

Gem::Specification.new do |spec|
  spec.name = 'ratomic-rack'
  spec.version = Ratomic::Rack::VERSION
  spec.authors = ['Ken C. Demanawa']
  spec.email = ['kenneth.c.demanawa@gmail.com']

  spec.summary = 'Experimental Rack integration for Ratomic LocalPool.'
  spec.description = <<~DESCRIPTION
    Ratomic::Rack investigates whether Ratomic's LocalPool can provide a
    prewarmed, Ractor-based execution layer behind a Puma/Rack server.
  DESCRIPTION
  spec.homepage = 'https://kanutocd.github.io/ratomic-rack'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 4.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/kanutocd/ratomic-rack'
  spec.metadata['changelog_uri'] = "#{spec.metadata['source_code_uri']}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.metadata['source_code_uri']}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir[
    'lib/**/*.rb',
    'sig/**/*.rbs',
    'README.md',
    'CHANGELOG.md',
    'LICENSE.txt'
  ]
  spec.require_paths = ['lib']

  spec.add_dependency 'ratomic', '~> 0.4.3'
end
