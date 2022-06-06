require 'flight_job_helper'
require_relative '../../../lib/flight_job/matcher'

RSpec.describe FlightJob::Matcher do
  let(:script_id_1) { "script-1" }
  let(:script_id_2) { "script-2" }

  context "scripts are loaded and filtered" do
    it "by only script ID" do
      opts = OpenStruct.new(id: "*log*")
      expect(FlightJob::Script.new(id: script_id_1).pass_filter?(opts)).to be true
      expect(FlightJob::Script.new(id: script_id_2).pass_filter?(opts)).to be false
    end
    it "by only template ID" do
      opts = OpenStruct.new(template: "*com*")
      expect(FlightJob::Script.new(id: script_id_1).pass_filter?(opts)).to be false
      expect(FlightJob::Script.new(id: script_id_2).pass_filter?(opts)).to be true
    end
  end
end
