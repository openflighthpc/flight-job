require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch
end

require "spec_helper"

ENV['flight_ENVIRONMENT'] ||= "test"
require_relative "../lib/flight"
require_relative "../lib/flight_job"

Flight.load_configuration

require_relative 'matchers/model'

RSpec.configure do |config|
  config.include FlightJob::Matchers::Model, type: :model
end
