require 'flight_job_helper'

RSpec.describe "FlightJob::Job::BrokenMetadata", type: :model do
  let(:config) { FlightJob.config }
  let(:job_dir) { File.join(config.jobs_dir, job_id) }
  let(:metadata_path) { File.join(config.job_dir, "metadata.yaml") }
  let(:job_id) { "invalid-job-state-bootstrapping" }

  context "invalid job is loaded" do
    it "loads when loading a single job" do
      # this means that the invalid job would appear when running info-job
      FakeFS.with_fresh do
        FakeFS::FileSystem.clone(File.join(__FILE__, "../../../../config"))
        FakeFS::FileSystem.clone(job_dir)

        x = FlightJob::Command.new(nil,nil)
        expect(x.load_job(job_id)).to be_truthy
      end
    end

    it "loads when loading all jobs" do
      # this means that the invalid job would appear when running list-jobs
      FakeFS.with_fresh do
        FakeFS::FileSystem.clone(File.join(__FILE__, "../../../../config"))
        FakeFS::FileSystem.clone(job_dir)

        expect(FlightJob::Job.load_all.length).to eq(1)
      end
    end
  end

  context "invalid job with complete metadata" do
    let(:job_id) { "invalid-job-state-bootstrapping" }
    subject(:job) {FlightJob::Job.new(id: job_id)}

    it "displays job_ID and scheduler_ID" do
      expect(job.decorate.id).to eq(job.id)
      expect(job.decorate.scheduler_id).to eq(job.metadata.scheduler_id)
    end
    it "displays a 'BROKEN' state" do
      expect(job.decorate.state).to eq("BROKEN")
    end
  end

  context "invalid job with metadata containing only scheduler ID" do
    let(:job_id) { "invalid-job-only-scheduler-id" }
    subject(:job) {FlightJob::Job.new(id: job_id)}

    it "displays job_ID and scheduler_ID" do
      expect(job.decorate.id).to eq(job.id)
      expect(job.decorate.scheduler_id).to eq(job.metadata.scheduler_id)
    end
    it "displays a 'BROKEN' state" do
      expect(job.decorate.state).to eq("BROKEN")
    end
  end

  context "invalid job with no scheduler ID available" do
    let(:job_id) { "invalid-job-empty-metadata" }
    subject(:job) {FlightJob::Job.new(id: job_id)}

    it "displays the job ID" do
      expect(job.decorate.id).to eq(job.id)
    end
    it "displays (none) for scheduler_ID" do
      expect(job.decorate.scheduler_id).to eq(nil)
    end
    it "displays a 'BROKEN' state" do
      expect(job.decorate.state).to eq("BROKEN")
    end
  end
end
