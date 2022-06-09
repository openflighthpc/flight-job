require 'flight_job_helper'
require_relative '../../lib/flight_job/matcher'

RSpec.describe FlightJob::Matcher do
  let(:attrs_1) { { foo: 'value-1', bar: 'value-2' } }
  let(:attrs_2) { { foo: '1-value', bar: '2-value' } }
  let(:attrs_3) { { foo: 'value-one', bar: 'value-two' } }

  context "filtering" do
    it "by multiple parameters" do
      filters = OpenStruct.new(foo: "*-1", bar: "*-2")
      expect(FlightJob::Matcher.new(filters, attrs_1).matches?).to be true
      expect(FlightJob::Matcher.new(filters, attrs_2).matches?).to be false
    end

    it "with multiple options for a single parameter" do
      filters = OpenStruct.new(foo: "*-1,1-*")
      expect(FlightJob::Matcher.new(filters, attrs_1).matches?).to be true
      expect(FlightJob::Matcher.new(filters, attrs_2).matches?).to be true
      expect(FlightJob::Matcher.new(filters, attrs_3).matches?).to be false
    end
  end

  context "reducing sensitivity to typos" do
    it "filters are case insensitive" do
      filters = OpenStruct.new(foo: "VALUE-1")
      expect(FlightJob::Matcher.new(filters, attrs_1).matches?).to be true
    end

    it "underscores are treated as hyphens" do
      filters = OpenStruct.new(foo: "*_1")
      expect(FlightJob::Matcher.new(filters, attrs_1).matches?).to be true
    end

    it "white spaces are ignored" do
      filters = OpenStruct.new(foo: "*-1 , 1-*")
      expect(FlightJob::Matcher.new(filters, attrs_1).matches?).to be true
      expect(FlightJob::Matcher.new(filters, attrs_2).matches?).to be true
    end
  end
end
