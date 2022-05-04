require 'flight_job_helper'

RSpec.describe "FlightJob::Script", type: :model do
  let(:config) { FlightJob.config }
  let(:script_id) { "valid-script" }
  let(:metadata_path) { File.join(config.scripts_dir, script_id, "metadata.yaml") }
  let(:metadata) { YAML.load_file(metadata_path) }
  subject(:script) { FlightJob::Script.new(id: script_id) }

  describe "metadata" do
    it "has the expected metadata path" do
      expect(script.metadata_path).to eq(metadata_path)
    end

    %w(created_at script_name).each do |attr|
      it "reads #{attr} from the metadata" do
        expect(script.send(attr)).to eq(metadata[attr])
      end
    end

    it "reads submission_answers from the metadata defaulting to {}" do
      expect(script.answers).to eq(metadata["answers"] || {})
    end
  end
end
