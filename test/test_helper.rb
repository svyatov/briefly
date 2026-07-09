# frozen_string_literal: true

if ENV["COVERAGE"]
  require "simplecov"

  if ENV["CI"]
    require "simplecov_json_formatter"
    SimpleCov.formatter = SimpleCov::Formatter::JSONFormatter
  end

  SimpleCov.start do
    add_filter "/test/"
    minimum_coverage 100
  end
end

require "minitest/autorun"

require "briefly"

# Base class that keeps the process-global handler registry from leaking between examples.
class BrieflyTest < Minitest::Test
  def teardown
    Briefly.errors.clear
    super
  end

  # A facade's definitions are deliberately unreachable from outside; these tests are white-box.
  def defs(facade) = facade.instance_variable_get(:@__defs)

  def memoized_names(facade) = defs(facade).select { |_name, defn| defn.memoized? }.keys

  def children(facade) = facade.instance_variable_get(:@__children)
end
