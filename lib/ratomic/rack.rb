# frozen_string_literal: true

require 'ratomic'
require_relative 'rack/version'
require_relative 'rack/handler'
require_relative 'rack/worker'

# Ratomic integration namespace.
module Ratomic
  # Rack integration namespace for the Ratomic execution experiment.
  module Rack
    # Base error for Ratomic::Rack failures.
    class Error < StandardError; end
  end
end
