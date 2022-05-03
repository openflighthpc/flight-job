require 'flight_job_helper'

RSpec.describe "FlightJob::ScriptMetadata", type: :model do

  context "creates metadata for valid script" do
    let(:template) { "some-template" }
    let(:script) { "valid-script"}

    subject(:metadata) { FlightJob::Script::ScriptMetadata.from_template(script) }

    it "sets created_at correctly" do
      expect(Time.parse(metadata.created_at)).to be_within(1).of(Time.now)
    end
  end

end
