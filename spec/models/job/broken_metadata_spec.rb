require 'flight_job_helper'

RSpec.describe "FlightJob::Job::BrokenMetadata", type: :model do
  let(:config) { FlightJob.config }
  let(:job_dir) { File.join(config.jobs_dir, job_id) }
  let(:metadata_path) { File.join(config.job_dir, "metadata.yaml") }

  context "invalid job is loaded" do
    let(:job_id) { "invalid-job-state-bootstrapping" }

    it "displays limited metadata" do

      FakeFS do
          FakeFS::FileSystem.clone(File.join(__FILE__, "../../../../config"))
          FakeFS::FileSystem.clone(job_dir)
          FakeFS::FileSystem.clone("/tmp/bundle/ruby/2.7.0/gems/activesupport-6.1.3")
          FakeFS::FileSystem.clone("/tmp/bundle/ruby/2.7.0/gems/activemodel-6.1.3")



          #FlightJob::Command.load_job(job_id)

        end

    end
  end
end