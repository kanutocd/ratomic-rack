# frozen_string_literal: true

require 'test_helper'

module Ratomic
  class TestRack < Minitest::Test
    def test_that_it_has_a_version_number
      refute_nil Rack::VERSION
    end
  end
end
