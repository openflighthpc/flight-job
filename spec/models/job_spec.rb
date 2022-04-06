require 'flight_job_helper'

RSpec.describe "FlightJob::Job", type: :model do
  let(:config) { FlightJob.config }
  let(:job_id) { "valid-job" }
  let(:metadata_path) { File.join(config.jobs_dir, job_id, "metadata.yaml") }
  let(:metadata) { YAML.load_file(metadata_path) }
  subject(:job) { FlightJob::Job.new(id: job_id) }

  describe "validations" do
    context "when job is valid when loaded" do
      let(:job_id) { "valid-job" }

      before(:each) { subject.valid?(:load) }

      it { expect(subject.errors).to be_empty }
      it { is_expected.not_to have_error(:metadata, 'is invalid') }
    end

    context "when job is valid when saved" do
      let(:job_id) { "valid-job" }

      before(:each) { subject.valid?(:save) }

      it { expect(subject.errors).to be_empty }
      it { is_expected.not_to have_error(:metadata, 'is invalid') }
    end

    context "when job is invalid when loaded" do
      let(:job_id) { "invalid-job" }

      before(:each) { subject.valid?(:load) }

      it { expect(subject.errors).not_to be_empty }
      it { is_expected.to have_error(:metadata, 'is invalid') }
    end

    context "when job is invalid when saved" do
      let(:job_id) { "invalid-job" }

      before(:each) { subject.valid?(:save) }

      it { expect(subject.errors).not_to be_empty }
      it { is_expected.to have_error(:metadata, 'is invalid') }
    end
  end

  it "has the given id" do
    expect(job.id).to eq job_id
  end

  describe "metadata" do
    before(:each) do
    end

    it "has the expected metadata path" do
      expect(job.metadata_path).to eq(metadata_path)
    end

    %w(created_at job_type results_dir scheduler_id script_id stdout_path stderr_path).each do |attr|
      it "reads #{attr} from the metadata" do
        expect(job.send(attr)).to eq(metadata[attr])
      end
    end

    it "reads submission_answers from the metadata defaulting to {}" do
      expect(job.submission_answers).to eq(metadata["submission_answers"] || {})
    end
  end
end
