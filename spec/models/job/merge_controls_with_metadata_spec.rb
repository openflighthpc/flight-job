require 'flight_job_helper'

RSpec.describe "FlightJob::Job::MergeControlsWithMetadata" do
  let(:config) { FlightJob.config }
  let(:job_id) { "job-with-controls-files" }
  let(:job_dir) { File.join(config.jobs_dir, job_id) }
  let(:metadata_path) { File.join(job_dir, "metadata.yaml") }
  let(:parsed_meta_file) { YAML.load_file(metadata_path) }

  let(:job) { FlightJob::Job.new(id: job_id) }

  it "it merges scheduler_id" do
    expect(parsed_meta_file["scheduler_id"]).to be_nil
    expect(job.controls_file("scheduler_id").read).to eq "some scheduler id"

    scheduler_id = job.metadata.scheduler_id
    expect(scheduler_id).to eq "some scheduler id"
  end

  it "it merges submit_status" do
    expect(parsed_meta_file["submit_status"]).to be_nil
    expect(job.controls_file("submit_status").read).to eq "0"

    expect(job.metadata.submit_status).to eq 0
  end

  it "it merges job_type" do
    expect(parsed_meta_file["job_type"]).to eq "SUBMITTING"
    expect(job.controls_file("job_type").read).to eq "BOOTSTRAPPING"

    expect(job.metadata.job_type).to eq "BOOTSTRAPPING"
  end

  it "doesn't break when metadata is invalid" do
    FakeFS do
      FakeFS::FileSystem.clone(File.join(__FILE__, "../../../../config"))
      FakeFS::FileSystem.clone(job_dir)
      File.write(metadata_path, YAML.dump(%w(this is not a yaml hash)))

      expect(job.metadata).to be_persisted
      expect(job.metadata.scheduler_id).to be_nil
      expect(job.metadata.submit_status).to be_nil
      expect(job.metadata.job_type).to be_nil
    end
  end
end
