require 'flight_job_helper'

RSpec.describe "FlightJob::ScriptMetadata", type: :model do

  context "creates metadata for valid script" do
    let(:config) { FlightJob.config }
    let(:template) { "some-template" }
    let(:script_id) { "valid-script" }
    let(:script_dir) { File.join(FlightJob.config.scripts_dir, script_id, 'metadata.yaml') }
    let(:script) { double("A script", id: script_id, metadata_path: script_dir) }

    subject(:script_metadata) { FlightJob::Script::Metadata.from_template(script) }

    it "sets created_at correctly" do
      puts "AAAAAAAAAAAAAAAAAA"
      puts script_metadata.inspect
      expect(Time.parse(script_metadata["created_at"])).to be_within(1).of(Time.now)
    end
  end

end
