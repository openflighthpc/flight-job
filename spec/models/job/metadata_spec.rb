require 'flight_job_helper'

RSpec.describe "FlightJob::Job::Metadata", type: :model do
  let(:config) { FlightJob.config }
  let(:job_id) { "valid-job" }
  let(:job_dir) { File.join(config.jobs_dir, job_id) }
  let(:metadata_path) { File.join(job_dir, "metadata.yaml") }
  let(:job) { double("A job", job_dir: job_dir, id: job_id) }
  subject(:metadata) { FlightJob::Job::Metadata.load_from_path(metadata_path, job) }

  describe "validations" do
    context "when job is valid" do
      let(:job_id) { "valid-job" }

      before(:each) { subject.valid? }

      it { expect(subject.errors).to be_empty }
      it { is_expected.not_to have_error(:metadata, 'is invalid') }
    end

    context "when job is invalid" do
      let(:job_id) { "invalid-job" }

      before(:each) { subject.valid? }

      it { expect(subject.errors).not_to be_empty }
      it { is_expected.to have_error(:metadata, 'is invalid') }
    end
  end

  describe "::from_script" do
    let(:script) { double("A script", id: "script-id", script_name: "script-name") }
    let(:answers) { {"q1" => "a1", "q2" => "a2", "q3" => "a3"} }

    subject(:metadata) { FlightJob::Job::Metadata.from_script(script, answers, job) }

    it "sets created_at correctly" do
      expect(Time.parse(metadata.created_at)).to be_within(1).of(Time.now)
    end
    it "sets job_type correctly" do
      expect(metadata.job_type).to eq "SUBMITTING"
    end
    it "sets script_id correctly" do
      expect(metadata.script_id).to eq script.id
    end
    it "sets rendered_path correctly" do
      expect(metadata.rendered_path).to eq File.join(job_dir, "script-name")
    end
    it "sets version correctly" do
      expect(metadata.version).to eq 2
    end
    it "sets submission_answers correctly" do
      expect(metadata.submission_answers).to eq answers
    end
  end

  describe "#with_save_point" do
    it "keeps the changes by default" do
      expect(metadata.job_type).not_to eq "some job type"
      metadata.with_save_point do
        metadata.job_type = "some job type"
      end
      expect(metadata.job_type).to eq "some job type"
    end

    it "permits restoring to the save point" do
      expect(metadata.job_type).not_to eq "some job type"
      metadata.with_save_point do
        metadata.job_type = "some job type"
        expect(metadata.job_type).to eq "some job type"
        metadata.restore_save_point
      end
      expect(metadata.job_type).not_to eq "some job type"
    end
  end

  describe "#save" do
    let(:job_id) { SecureRandom.uuid }
    let(:script) { double("A script", id: "script-id", script_name: "script-name") }
    let(:answers) { {"q1" => "a1", "q2" => "a2", "q3" => "a3"} }

    subject(:metadata) { FlightJob::Job::Metadata.from_script(script, answers, job) }

    context "when valid" do
      it "write the metadata to disk" do
        # Use FakeFS to avoid accumulating lots of extra test files.
        FakeFS.with do
          FakeFS::FileSystem.clone(File.join(__FILE__, "../../../../config"))
          expect(metadata).not_to be_persisted
          expect(metadata.valid?(:load)).to be true

          metadata.save

          expect(metadata).to be_persisted
          expect(File.read(metadata.path)).to eq YAML.dump(metadata.instance_variable_get(:@hash))
        end
      end
    end

    context "when invalid" do
      it "write the metadata to disk" do
        metadata.job_type = "INVALID"
        expect(metadata).not_to be_persisted
        expect(metadata.valid?(:load)).to be false

        expect { metadata.save }.to raise_error(FlightJob::InternalError)

        expect(metadata).not_to be_persisted
      end
    end
  end

  describe "#reload" do
    it "reloads the metadata to the original value" do
      original = metadata.job_type
      metadata.job_type = "some job type"

      expect { metadata.reload }.to change { metadata.job_type }
        .from("some job type")
        .to(original)
    end

    it "reads new values from the metadata file" do
      original = metadata.script_id
      altered = original + " some changes"
      FakeFS.with do
        FakeFS::FileSystem.clone(job_dir)
        md = YAML.load_file(metadata.path)
        md["script_id"] = altered
        File.write(metadata.path, YAML.dump(md))

        expect { metadata.reload }.to change { metadata.script_id }
          .from(original)
          .to(altered)
      end
    end
  end
end
