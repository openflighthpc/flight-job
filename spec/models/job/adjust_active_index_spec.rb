require 'flight_job_helper'

RSpec.describe FlightJob::Job::AdjustActiveIndex do
  let(:config) { FlightJob.config }

  context "non-terminal job is initialized" do
    let(:job_id) { "non-terminal-no-active-index" }
    let(:job_dir) { File.join(config.jobs_dir, job_id) }
    let(:active_index_path) { File.join(job_dir, "active.index") }
    it "creates active index file" do
      FakeFS do
        clone_job_directory(job_dir)
        expect(File).not_to exist(active_index_path)
        FlightJob::Job.new(id: job_id)
        expect(File).to exist(active_index_path)
      end
    end
  end

  context "terminal job is initialized" do
    let(:job_id) { "terminal-with-active-index" }
    let(:job_dir) { File.join(config.jobs_dir, job_id) }
    let(:active_index_path) { File.join(job_dir, "active.index") }
    it "removes active.index file" do
      FakeFS do
        clone_job_directory(job_dir)
        expect(File).to exist(active_index_path)
        FlightJob::Job.new(id: job_id)
        expect(File).not_to exist(active_index_path)
      end
    end
  end

  context "job reaches terminal state and is saved" do
    let(:job_id) { "non-terminal-with-active-index" }
    let(:job_dir) { File.join(config.jobs_dir, job_id) }
    let(:active_index_path) { File.join(job_dir, "active.index") }
    it "removes active.index file" do
      FakeFS do
        clone_job_directory(job_dir)
        job = FlightJob::Job.new(id: job_id)
        expect(File).to exist(active_index_path)
        job.metadata.state = "CANCELLED"
        job.save
        expect(File).not_to exist(active_index_path)
      end
    end
  end

  def clone_job_directory(job_dir)
    FakeFS::FileSystem.clone(File.join(__FILE__, "../../../../config"))
    FakeFS::FileSystem.clone(job_dir)
  end
end