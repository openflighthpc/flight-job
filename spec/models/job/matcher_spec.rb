require 'flight_job_helper'
require_relative '../../../lib/flight_job/matcher'

RSpec.describe FlightJob::Matcher do
  let(:job_id_1) { "matcher-job-1" }
  let(:job_id_2) { "matcher-job-2" }
  let(:job_id_3) { "matcher-job-3" }
  let(:job_id_array) { "matcher-job-array" }
  let(:job_id_invalid) { "invalid-job" }

  context "jobs are loaded and filtered" do
    it "by only job ID" do
      opts = OpenStruct.new(id: "*1")
      expect(FlightJob::Job.new(id: job_id_1).pass_filter?(opts)).to be true
      expect(FlightJob::Job.new(id: job_id_2).pass_filter?(opts)).to be false
    end

    it "by only script ID" do
      opts = OpenStruct.new(script: "second*")
      expect(FlightJob::Job.new(id: job_id_1).pass_filter?(opts)).to be false
      expect(FlightJob::Job.new(id: job_id_2).pass_filter?(opts)).to be true
    end

    it "by only job state (desktop session)" do
      opts = OpenStruct.new(state: "*NN*")
      expect(FlightJob::Job.new(id: job_id_1).pass_filter?(opts)).to be true
      expect(FlightJob::Job.new(id: job_id_2).pass_filter?(opts)).to be false
    end

    it "by only job state (array job)" do
      opts = OpenStruct.new(state: "COMPLETED")
      expect(FlightJob::Job.new(id: job_id_array).pass_filter?(opts)).to be true
    end

    it "by multiple parameters" do
      opts = OpenStruct.new(id: "*1", script: "first*", state: "*NN*")
      expect(FlightJob::Job.new(id: job_id_1).pass_filter?(opts)).to be true
      expect(FlightJob::Job.new(id: job_id_2).pass_filter?(opts)).to be false
    end

    it "with multiple options for a single parameter" do
      opts = OpenStruct.new(state: "RUNNING,COMPLETED")
      expect(FlightJob::Job.new(id: job_id_1).pass_filter?(opts)).to be true
      expect(FlightJob::Job.new(id: job_id_2).pass_filter?(opts)).to be true
      expect(FlightJob::Job.new(id: job_id_3).pass_filter?(opts)).to be false
    end

    it "invalid jobs show broken state" do
      opts = OpenStruct.new(state: "BROKEN")
      expect(FlightJob::Job.new(id: job_id_invalid).pass_filter?(opts)).to be true
    end
  end

  context "reducing sensitivity to typos" do
    it "filters are case insensitive" do
      opts = OpenStruct.new(state: "running")
      expect(FlightJob::Job.new(id: job_id_1).pass_filter?(opts)).to be true
    end

    it "underscores are treated as hyphens" do
      opts = OpenStruct.new(id: "*_1")
      expect(FlightJob::Job.new(id: job_id_1).pass_filter?(opts)).to be true
    end

    it "white spaces are ignored" do
      opts = OpenStruct.new(id: "*_1 , *_2")
      expect(FlightJob::Job.new(id: job_id_1).pass_filter?(opts)).to be true
      expect(FlightJob::Job.new(id: job_id_2).pass_filter?(opts)).to be true
    end
  end

  context "jobs are loaded with no filter" do
    it "all jobs are loaded" do
      opts = OpenStruct.new
      expect(FlightJob::Job.new(id: job_id_1).pass_filter?(opts)).to be true
      expect(FlightJob::Job.new(id: job_id_2).pass_filter?(opts)).to be true
    end
  end
end
