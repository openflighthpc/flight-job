require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch
end

require "pp"
require "spec_helper"
require "fakefs/spec_helpers"

ENV['flight_ENVIRONMENT'] ||= "test"
require_relative "../lib/flight"
require_relative "../lib/flight_job"

Flight.load_configuration

require_relative 'matchers/model'

RSpec.configure do |config|
  config.include FlightJob::Matchers::Model, type: :model

  config.before(:suite) do
    # Our use of FakeFS can cause problems when translations and localizations
    # are lazily loaded.  We ensure that all needed localizations are loaded
    # prior to the suite running.
    I18n.localize(Time.now)
  end
end
