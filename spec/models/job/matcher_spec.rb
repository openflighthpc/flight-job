require 'flight_job_helper'
require_relative '../../../lib/flight_job/matcher'

RSpec.describe FlightJob::Matcher do
  let(:config) { FlightJob.config }
  let(:jobs_dir) { config.jobs_dir }
  let(:job_id_1) { "matcher-job-1" }
  let(:job_id_2) { "matcher-job-2" }
  let(:job_id_3) { "matcher-job-3" }

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

    it "by only job state" do
      opts = OpenStruct.new(state: "*NN*")
      expect(FlightJob::Job.new(id: job_id_1).pass_filter?(opts)).to be true
      expect(FlightJob::Job.new(id: job_id_2).pass_filter?(opts)).to be false
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
  end

  context "jobs are loaded with no filter" do
    it "all jobs are loaded" do
      opts = OpenStruct.new
      expect(FlightJob::Job.new(id: job_id_1).pass_filter?(opts)).to be true
      expect(FlightJob::Job.new(id: job_id_2).pass_filter?(opts)).to be true
    end
  end
end
