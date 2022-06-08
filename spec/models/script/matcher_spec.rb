require 'flight_job_helper'
require_relative '../../../lib/flight_job/matcher'

RSpec.describe 'Script filtering' do
  let(:script_id_1) { "matcher-script-1" }
  let(:script_id_2) { "matcher-script-2" }
  let(:script_id_3) { "matcher-script-3" }

  context "scripts are loaded and filtered" do
    it "by only script ID" do
      opts = OpenStruct.new(id: "*-1")
      expect(FlightJob::Script.new(id: script_id_1).pass_filter?(opts)).to be true
      expect(FlightJob::Script.new(id: script_id_2).pass_filter?(opts)).to be false
    end

    it "by only template ID" do
      opts = OpenStruct.new(template: "*com*")
      expect(FlightJob::Script.new(id: script_id_1).pass_filter?(opts)).to be false
      expect(FlightJob::Script.new(id: script_id_2).pass_filter?(opts)).to be true
    end
  end

  context "scripts are loaded with no filter" do
    it "all scripts are loaded" do
      opts = OpenStruct.new
      expect(FlightJob::Script.new(id: script_id_1).pass_filter?(opts)).to be true
      expect(FlightJob::Script.new(id: script_id_2).pass_filter?(opts)).to be true
    end
  end
end
