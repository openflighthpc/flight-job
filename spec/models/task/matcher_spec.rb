require 'flight_job_helper'
require_relative '../../../lib/flight_job/matcher'

RSpec.describe FlightJob::Matcher do
  let(:job_id) { "matcher-job-array" }

  context "tasks are loaded and filtered" do
    it "by task state (single filter)" do
      opts = OpenStruct.new(state: "com*")
      expect(FlightJob::Task.new(job_id: job_id, index: 1).pass_filter?(opts)).to be true
      expect(FlightJob::Task.new(job_id: job_id, index: 2).pass_filter?(opts)).to be false
    end

    it "by task state (multiple filters)" do
      opts = OpenStruct.new(state: "RUNNING,COMPLETED")
      expect(FlightJob::Task.new(job_id: job_id, index: 1).pass_filter?(opts)).to be true
      expect(FlightJob::Task.new(job_id: job_id, index: 2).pass_filter?(opts)).to be false
      expect(FlightJob::Task.new(job_id: job_id, index: 3).pass_filter?(opts)).to be true
    end
  end

  context "tasks are loaded with no filter" do
    it "all tasks are loaded" do
      opts = OpenStruct.new
      expect(FlightJob::Task.new(job_id: job_id, index: 1).pass_filter?(opts)).to be true
      expect(FlightJob::Task.new(job_id: job_id, index: 2).pass_filter?(opts)).to be true
    end
  end
end